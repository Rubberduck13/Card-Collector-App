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
    
    /// Scans a live camera pixel frame to detect if a rectangle trading card is present
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
    
    /// Extracts the card serial index number string from the bottom layout margin of the card boundary
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
    
    /// OLD (fake) centering function — kept for reference/comparison, no longer used by the app
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
    
    /// NEW (real) centering function — reads actual pixel brightness to find the printed border
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
        let context = CIContext()
        guard let correctedCGImage = context.createCGImage(correctedImage, from: correctedImage.extent),
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
        
        func scanLineForBorder(edge: String, lineOffset: Int) -> Int? {
            let scanLength: Int
            switch edge {
            case "left", "right": scanLength = width / 2
            default: scanLength = height / 2
            }
            var prevBrightness: Int? = nil
            var maxJump = 0
            var borderWidth: Int? = nil
            
            for i in 0..<scanLength {
                let currentBrightness: Int
                switch edge {
                case "left": currentBrightness = brightness(x: i, y: lineOffset)
                case "right": currentBrightness = brightness(x: width - 1 - i, y: lineOffset)
                case "top": currentBrightness = brightness(x: lineOffset, y: i)
                default: currentBrightness = brightness(x: lineOffset, y: height - 1 - i)
                }
                if let prev = prevBrightness, i > 3 {
                    let jump = abs(currentBrightness - prev)
                    if jump > maxJump {
                        maxJump = jump
                        borderWidth = i
                    }
                }
                prevBrightness = currentBrightness
            }
            return maxJump > 15 ? borderWidth : nil
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
    
    private func fallbackCentering() -> CenteringResult {
        CenteringResult(leftRightRatio: (50, 50), topBottomRatio: (50, 50), passesPSA10: true, passesBGS10: true)
    }
}
