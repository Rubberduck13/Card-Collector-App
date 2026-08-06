import Foundation
import CoreGraphics
import Vision
import UIKit

public struct CenteringResult {
    public let leftRightRatio: (left: Double, right: Double)
    public let topBottomRatio: (top: Double, bottom: Double)
    public let passesPSA10: Bool
    public let passesBGS10: Bool
}

public class CenteringAnalyzer {

    public init() {}

    // MARK: - Multi-Frame Averaging State
    // Rolling buffer of recent single-frame centering readings. Averaging (median) across
    // several frames is what actually kills frame-to-frame swing — a single frame is noisy
    // (lighting flicker, sensor noise, micro-shake); several frames held over ~1-2 seconds
    // converge on the card's true centering.
    private var recentSamples: [CenteringResult] = []
    private let maxSampleBufferSize = 8
    private let minimumSamplesForStableReading = 4
    // If a new single-frame reading differs from the current running median by more than
    // this many percentage points, treat it as the card having moved/been repositioned
    // (not just noise) and start the buffer over rather than blending it in.
    private let outlierRejectionThreshold = 20.0

    // FIXED (crash/lockup root cause): the buffer above is written to from the camera's
    // background Vision-processing thread (via analyzeCenteringAveraged, called from
    // processLiveCameraFrame's Task) AND cleared from the main thread (resetSampleBuffer,
    // called on commit/reset). Two threads mutating the same array with no coordination is
    // a data race — this is almost certainly what caused the intermittent crashes/lockups
    // after saving to Vault. All access to recentSamples now goes through this serial queue
    // so reads and writes can never overlap, regardless of which thread calls in.
    private let bufferAccessQueue = DispatchQueue(label: "com.thejudge.centeringanalyzer.bufferqueue")

    /// Call this whenever card detection is lost, the scan phase resets, or a new card
    /// is presented — clears the rolling buffer so old samples don't bleed into a new scan.
    public func resetSampleBuffer() {
        bufferAccessQueue.sync {
            recentSamples.removeAll()
        }
    }

    /// True once enough consistent samples have accumulated that the averaged reading
    /// can be trusted (used to gate the "Lock & Advance" button / auto-advance on the
    /// front-centering phase).
    public var isStableReading: Bool {
        bufferAccessQueue.sync {
            recentSamples.count >= minimumSamplesForStableReading
        }
    }

    /// How many consistent samples are currently buffered (0...maxSampleBufferSize).
    /// Useful for showing "Hold steady... 3/4" style progress in the UI.
    public var currentSampleCount: Int {
        bufferAccessQueue.sync {
            recentSamples.count
        }
    }

    public func detectCardRectangle(in image: CGImage, completion: @escaping (VNRectangleObservation?) -> Void) {
        let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])

        let rectangleRequest = VNDetectRectanglesRequest { request, error in
            guard error == nil,
                  let results = request.results as? [VNRectangleObservation],
                  let primaryCard = results.first else {
                completion(nil)
                return
            }
            completion(primaryCard)
        }

        rectangleRequest.minimumAspectRatio = 0.55
        rectangleRequest.maximumAspectRatio = 0.85
        rectangleRequest.minimumConfidence = 0.85

        try? requestHandler.perform([rectangleRequest])
    }

    public func extractCardIdentifierText(from image: CGImage, cardBoundingBox: VNRectangleObservation, completion: @escaping (String?) -> Void) {
        let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])

        let textRequest = VNRecognizeTextRequest { request, error in
            guard error == nil, let textObservations = request.results as? [VNRecognizedTextObservation] else {
                completion(nil)
                return
            }

            for observation in textObservations {
                guard let candidateText = observation.topCandidates(1).first?.string else { continue }
                let normalizedText = candidateText.replacingOccurrences(of: " ", with: "")
                if normalizedText.contains("/") {
                    completion(normalizedText)
                    return
                }
            }
            completion(nil)
        }

        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = false
        textRequest.regionOfInterest = CGRect(x: 0.0, y: 0.0, width: 1.0, height: 0.15)

        try? requestHandler.perform([textRequest])
    }

    /// OLD (fake) centering function — kept for reference, no longer used
    public func analyzeCentering(from observation: VNRectangleObservation) -> CenteringResult {
        let absoluteLeftBoundary: Double = Double(observation.topLeft.x)
        let absoluteRightBoundary: Double = 1.0 - Double(observation.topRight.x)
        let absoluteTopBoundary: Double = 1.0 - Double(observation.topLeft.y)
        let absoluteBottomBoundary: Double = Double(observation.bottomLeft.y)

        let simulatedArtFrameOffsetLeft: Double = absoluteLeftBoundary + 0.045
        let simulatedArtFrameOffsetRight: Double = absoluteRightBoundary + 0.048
        let simulatedArtFrameOffsetTop: Double = absoluteTopBoundary + 0.051
        let simulatedArtFrameOffsetBottom: Double = absoluteBottomBoundary + 0.050

        let leftBorderWidth: Double = simulatedArtFrameOffsetLeft - absoluteLeftBoundary
        let rightBorderWidth: Double = simulatedArtFrameOffsetRight - absoluteRightBoundary
        let totalHorizontalBordersCombined: Double = leftBorderWidth + rightBorderWidth

        let leftPercentage: Double = totalHorizontalBordersCombined > 0.0 ? (leftBorderWidth / totalHorizontalBordersCombined) * 100.0 : 50.0
        let rightPercentage: Double = totalHorizontalBordersCombined > 0.0 ? (rightBorderWidth / totalHorizontalBordersCombined) * 100.0 : 50.0

        let topBorderWidth: Double = simulatedArtFrameOffsetTop - absoluteTopBoundary
        let bottomBorderWidth: Double = simulatedArtFrameOffsetBottom - absoluteBottomBoundary
        let totalVerticalBordersCombined: Double = topBorderWidth + bottomBorderWidth

        let topPercentage: Double = totalVerticalBordersCombined > 0.0 ? (topBorderWidth / totalVerticalBordersCombined) * 100.0 : 50.0
        let bottomPercentage: Double = totalVerticalBordersCombined > 0.0 ? (bottomBorderWidth / totalVerticalBordersCombined) * 100.0 : 50.0

        let passesPSA10: Bool = leftPercentage >= 40.0 && leftPercentage <= 60.0 && topPercentage >= 40.0 && topPercentage <= 60.0
        let passesBGS10: Bool = leftPercentage >= 48.0 && leftPercentage <= 52.0 && topPercentage >= 48.0 && topPercentage <= 52.0

        return CenteringResult(
            leftRightRatio: (leftPercentage, rightPercentage),
            topBottomRatio: (topPercentage, bottomPercentage),
            passesPSA10: passesPSA10,
            passesBGS10: passesBGS10
        )
    }

    /// NEW (real, improved) SINGLE-FRAME centering function — looks for a SUSTAINED shift in
    /// brightness, not just the single sharpest pixel-to-pixel jump. This avoids getting fooled
    /// by a logo, text, or color block near the edge, which can look like a sharper "border"
    /// than the real, more gradual transition into the card's artwork.
    ///
    /// FIXED: added an orientation lock. Vision reports topLeft/topRight/bottomLeft/bottomRight
    /// in the CAMERA IMAGE's coordinate space, not the card's. If the card (or phone) is held
    /// sideways relative to the card's natural portrait shape, "left border" and "top border"
    /// stop meaning the same physical edges from scan to scan. After perspective correction,
    /// if the corrected image comes out wider than it is tall, we rotate it 90° so every
    /// downstream measurement is always relative to the card's portrait orientation.
    ///
    /// NOTE: for a stable, trustworthy reading (not just a single frame), call
    /// `analyzeCenteringAveraged` instead — it wraps this function with multi-frame median
    /// averaging and outlier rejection.
    public func analyzeCenteringReal(from observation: VNRectangleObservation, in cgImage: CGImage) -> CenteringResult {
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent
        let topLeft = CGPoint(x: observation.topLeft.x * extent.width, y: observation.topLeft.y * extent.height)
        let topRight = CGPoint(x: observation.topRight.x * extent.width, y: observation.topRight.y * extent.height)
        let bottomLeft = CGPoint(x: observation.bottomLeft.x * extent.width, y: observation.bottomLeft.y * extent.height)
        let bottomRight = CGPoint(x: observation.bottomRight.x * extent.width, y: observation.bottomRight.y * extent.height)

        guard let perspectiveFilter = CIFilter(name: "CIPerspectiveCorrection") else { return fallbackCentering() }
        perspectiveFilter.setValue(ciImage, forKey: kCIInputImageKey)
        perspectiveFilter.setValue(CIVector(cgPoint: topLeft), forKey: "inputTopLeft")
        perspectiveFilter.setValue(CIVector(cgPoint: topRight), forKey: "inputTopRight")
        perspectiveFilter.setValue(CIVector(cgPoint: bottomLeft), forKey: "inputBottomLeft")
        perspectiveFilter.setValue(CIVector(cgPoint: bottomRight), forKey: "inputBottomRight")

        guard let correctedImage = perspectiveFilter.outputImage else { return fallbackCentering() }

        // NEW: orientation lock. A standard trading card is taller than it is wide. If the
        // perspective-corrected result is wider than it is tall, the card was captured
        // sideways — rotate it 90° (always the same direction, for consistency) so "left/
        // right" and "top/bottom" refer to the same physical edges every time regardless of
        // how the phone was held.
        var orientedImage = correctedImage
        let correctedExtent = correctedImage.extent
        if correctedExtent.width > correctedExtent.height {
            let rotated = correctedImage.transformed(by: CGAffineTransform(rotationAngle: -CGFloat.pi / 2))
            orientedImage = rotated.transformed(by: CGAffineTransform(
                translationX: -rotated.extent.origin.x,
                y: -rotated.extent.origin.y
            ))
        }

        let context = CIContext()
        guard let correctedCGImage = context.createCGImage(orientedImage, from: orientedImage.extent),
              let pixelData = correctedCGImage.dataProvider?.data,
              let buffer = CFDataGetBytePtr(pixelData) else {
            return fallbackCentering()
        }

        let width = correctedCGImage.width
        let height = correctedCGImage.height
        let bytesPerPixel = correctedCGImage.bitsPerPixel / 8
        let bytesPerRow = correctedCGImage.bytesPerRow
        let dataLength = CFDataGetLength(pixelData)

        func brightness(x: Int, y: Int) -> Int {
            let offset = y * bytesPerRow + x * bytesPerPixel
            guard offset + 2 < dataLength, offset >= 0 else { return 0 }
            let r = Int(buffer[offset])
            let g = Int(buffer[offset + 1])
            let b = Int(buffer[offset + 2])
            return (r + g + b) / 3
        }

        // Finds where brightness SUSTAINABLY diverges from the border's own baseline color,
        // rather than reacting to a single sharp spike.
        func scanLineForBorder(edge: String, lineOffset: Int) -> Int? {
            let scanLength: Int
            switch edge {
            case "left", "right": scanLength = width / 2
            default: scanLength = height / 2
            }
            guard scanLength > 12 else { return nil }

            func pixelAt(_ i: Int) -> Int {
                switch edge {
                case "left": return brightness(x: i, y: lineOffset)
                case "right": return brightness(x: width - 1 - i, y: lineOffset)
                case "top": return brightness(x: lineOffset, y: i)
                default: return brightness(x: lineOffset, y: height - 1 - i)
                }
            }

            // Baseline = average brightness of the first few pixels (the border itself,
            // right at the card's cut edge)
            let baselineSampleCount = 4
            var baselineSum = 0
            for i in 0..<baselineSampleCount { baselineSum += pixelAt(i) }
            let baseline = baselineSum / baselineSampleCount

            let divergenceThreshold = 30
            let sustainedRunRequired = 5

            var i = baselineSampleCount
            while i < scanLength - sustainedRunRequired {
                let diff = abs(pixelAt(i) - baseline)
                if diff > divergenceThreshold {
                    // Confirm this isn't just a one-pixel blip: check the next several
                    // pixels also diverge from baseline before accepting this as the border
                    var sustained = true
                    for offset in 1...sustainedRunRequired {
                        if abs(pixelAt(i + offset) - baseline) <= divergenceThreshold {
                            sustained = false
                            break
                        }
                    }
                    if sustained { return i }
                }
                i += 1
            }
            return nil
        }

        func findBorderWidth(edge: String) -> Double {
            let sampleCount = 7
            let dimension = (edge == "left" || edge == "right") ? height : width
            let margin = dimension / 4
            var results: [Int] = []

            for sample in 0..<sampleCount {
                let position = margin + (sample * (dimension - 2 * margin) / (sampleCount - 1))
                if let w = scanLineForBorder(edge: edge, lineOffset: position) {
                    results.append(w)
                }
            }

            guard !results.isEmpty else { return 12 }
            let sorted = results.sorted()
            return Double(sorted[sorted.count / 2])
        }

        let leftBorder = findBorderWidth(edge: "left")
        let rightBorder = findBorderWidth(edge: "right")
        let topBorder = findBorderWidth(edge: "top")
        let bottomBorder = findBorderWidth(edge: "bottom")

        let totalH = leftBorder + rightBorder
        let totalV = topBorder + bottomBorder
        let leftPct = totalH > 0 ? (leftBorder / totalH) * 100 : 50
        let rightPct = 100 - leftPct
        let topPct = totalV > 0 ? (topBorder / totalV) * 100 : 50
        let bottomPct = 100 - topPct

        let passesPSA10 = leftPct >= 40 && leftPct <= 60 && topPct >= 40 && topPct <= 60
        let passesBGS10 = leftPct >= 48 && leftPct <= 52 && topPct >= 48 && topPct <= 52

        return CenteringResult(
            leftRightRatio: (leftPct, rightPct),
            topBottomRatio: (topPct, bottomPct),
            passesPSA10: passesPSA10,
            passesBGS10: passesBGS10
        )
    }

    /// Multi-frame averaged centering. Call this once per live camera frame instead of calling
    /// `analyzeCenteringReal` directly. Internally it runs the single-frame scan, then folds
    /// the result into a rolling buffer and returns the MEDIAN of recent samples — which is
    /// dramatically more stable than any single frame, because random per-frame noise
    /// (lighting flicker, sensor noise, hand micro-shake) mostly cancels out across samples,
    /// while the card's real, unchanging centering stays put.
    ///
    /// If a new frame's reading is wildly different from the current running median, that's
    /// treated as a sign the card was moved/repositioned (not just noise) — the buffer resets
    /// so stale readings from before the move don't get blended into the new position.
    ///
    /// FIXED: all buffer reads/writes now happen inside bufferAccessQueue.sync, so this is
    /// safe to call from a background thread (as processLiveCameraFrame does) at the same
    /// time resetSampleBuffer() is called from the main thread.
    public func analyzeCenteringAveraged(from observation: VNRectangleObservation, in cgImage: CGImage) -> CenteringResult {
        // The pixel-level scan itself doesn't touch shared state, so it can run outside the
        // lock — only the buffer read/mutate/return needs to be serialized.
        let singleFrameResult = analyzeCenteringReal(from: observation, in: cgImage)

        return bufferAccessQueue.sync {
            if let currentMedian = medianResult(from: recentSamples),
               !isSampleConsistent(singleFrameResult, with: currentMedian) {
                recentSamples.removeAll()
            }

            recentSamples.append(singleFrameResult)
            if recentSamples.count > maxSampleBufferSize {
                recentSamples.removeFirst()
            }

            return medianResult(from: recentSamples) ?? singleFrameResult
        }
    }

    private func isSampleConsistent(_ sample: CenteringResult, with median: CenteringResult) -> Bool {
        let leftDelta = abs(sample.leftRightRatio.left - median.leftRightRatio.left)
        let topDelta = abs(sample.topBottomRatio.top - median.topBottomRatio.top)
        return leftDelta < outlierRejectionThreshold && topDelta < outlierRejectionThreshold
    }

    private func medianResult(from samples: [CenteringResult]) -> CenteringResult? {
        guard !samples.isEmpty else { return nil }
        let lefts = samples.map { $0.leftRightRatio.left }.sorted()
        let tops = samples.map { $0.topBottomRatio.top }.sorted()
        let medianLeft = lefts[lefts.count / 2]
        let medianTop = tops[tops.count / 2]
        let medianRight = 100 - medianLeft
        let medianBottom = 100 - medianTop

        let passesPSA10 = medianLeft >= 40 && medianLeft <= 60 && medianTop >= 40 && medianTop <= 60
        let passesBGS10 = medianLeft >= 48 && medianLeft <= 52 && medianTop >= 48 && medianTop <= 52

        return CenteringResult(
            leftRightRatio: (medianLeft, medianRight),
            topBottomRatio: (medianTop, medianBottom),
            passesPSA10: passesPSA10,
            passesBGS10: passesBGS10
        )
    }

    private func fallbackCentering() -> CenteringResult {
        CenteringResult(leftRightRatio: (50, 50), topBottomRatio: (50, 50), passesPSA10: true, passesBGS10: true)
    }
}
