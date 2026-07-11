import Foundation
import CoreImage
import CoreGraphics
import Vision

public struct CenteringResult {
    public let horizontalRatio: Double   // Left / (Left + Right)
    public let verticalRatio: Double     // Top / (Top + Bottom)

    public let leftBorder: CGFloat
    public let rightBorder: CGFloat
    public let topBorder: CGFloat
    public let bottomBorder: CGFloat

    public var horizontalPercent: (left: Double, right: Double) {
        let left = horizontalRatio * 100.0
        return (left, 100.0 - left)
    }

    public var verticalPercent: (top: Double, bottom: Double) {
        let top = verticalRatio * 100.0
        return (top, 100.0 - top)
    }

    public var horizontalOffset: Double {
        abs(horizontalRatio - 0.5) * 200.0
    }

    public var verticalOffset: Double {
        abs(verticalRatio - 0.5) * 200.0
    }

    public var isPerfect5050: Bool {
        abs(horizontalRatio - 0.5) < 0.001 &&
        abs(verticalRatio - 0.5) < 0.001
    }
}

public enum CenteringAnalyzerError: Error {
    case cardNotFound
    case invalidImage
    case unableToProcess
}

public final class CenteringAnalyzer {

    private let ciContext = CIContext()

    public init() {}

    /// Analyzes a card image and estimates border centering.
    /// Assumes the image is cropped closely around a single card.
    public func analyze(ciImage: CIImage) throws -> CenteringResult {

        guard let cardRect = detectCardBounds(in: ciImage) else {
            throw CenteringAnalyzerError.cardNotFound
        }

        let crop = ciImage.cropped(to: cardRect)

        let innerRect = try detectArtworkBounds(in: crop)

        let left = innerRect.minX
        let right = crop.extent.width - innerRect.maxX

        let top = crop.extent.height - innerRect.maxY
        let bottom = innerRect.minY

        let horizontalRatio = Double(left / max(left + right, 1))
        let verticalRatio = Double(top / max(top + bottom, 1))

        return CenteringResult(
            horizontalRatio: horizontalRatio,
            verticalRatio: verticalRatio,
            leftBorder: left,
            rightBorder: right,
            topBorder: top,
            bottomBorder: bottom
        )
    }

    // MARK: - Card Detection

    private func detectCardBounds(in image: CIImage) -> CGRect? {

        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.55
        request.maximumAspectRatio = 0.80
        request.minimumConfidence = 0.70
        request.maximumObservations = 1
        request.minimumSize = 0.20
        request.quadratureTolerance = 20

        let handler = VNImageRequestHandler(ciImage: image)

        do {
            try handler.perform([request])

            guard let observation = request.results?.first else {
                return nil
            }

            return observation.boundingBox.toImageRect(image.extent)

        } catch {
            return nil
        }
    }

    // MARK: - Artwork Detection

    /// Attempts to locate the inner artwork box by detecting strong edges.
    private func detectArtworkBounds(in image: CIImage) throws -> CGRect {

        let edges = image
            .applyingFilter("CIEdges", parameters: [
                kCIInputIntensityKey: 8.0
            ])

        guard let cgImage = ciContext.createCGImage(edges, from: edges.extent) else {
            throw CenteringAnalyzerError.invalidImage
        }

        guard let data = cgImage.dataProvider?.data else {
            throw CenteringAnalyzerError.invalidImage
        }

        let ptr = CFDataGetBytePtr(data)!

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow

        var minX = width
        var maxX = 0
        var minY = height
        var maxY = 0

        let threshold: UInt8 = 45

        for y in 0..<height {

            for x in 0..<width {

                let offset = y * bytesPerRow + x * 4

                let value = ptr[offset]

                if value > threshold {

                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }

                }
            }
        }

        if maxX <= minX || maxY <= minY {
            throw CenteringAnalyzerError.unableToProcess
        }

        let inset: CGFloat = 3

        return CGRect(
            x: CGFloat(minX) + inset,
            y: CGFloat(minY) + inset,
            width: CGFloat(maxX - minX) - inset * 2,
            height: CGFloat(maxY - minY) - inset * 2
        )
    }
}

// MARK: - Helpers

private extension VNRectangleObservation {

    func boundingBoxToCGRect() -> CGRect {
        CGRect(
            x: boundingBox.origin.x,
            y: boundingBox.origin.y,
            width: boundingBox.width,
            height: boundingBox.height
        )
    }
}

private extension CGRect {

    func normalizedToImage(_ imageRect: CGRect) -> CGRect {

        CGRect(
            x: origin.x * imageRect.width,
            y: origin.y * imageRect.height,
            width: width * imageRect.width,
            height: height * imageRect.height
        )
    }
}

private extension CGRect {

    var flippedY: CGRect {
        CGRect(
            x: minX,
            y: maxY,
            width: width,
            height: height
        )
    }
}

private extension CGRect {

    func clamped(to bounds: CGRect) -> CGRect {
        intersection(bounds)
    }
}

private extension CGRect {

    init(observation: VNRectangleObservation, imageExtent: CGRect) {
        self = observation.boundingBox.toImageRect(imageExtent)
    }
}

private extension CGRect {

    func centered() -> CGPoint {
        CGPoint(
            x: midX,
            y: midY
        )
    }
}

private extension CGRect {

    func expanded(by value: CGFloat) -> CGRect {
        insetBy(dx: -value, dy: -value)
    }
}

private extension CGRect {

    func scaled(_ factor: CGFloat) -> CGRect {

        CGRect(
            x: origin.x * factor,
            y: origin.y * factor,
            width: width * factor,
            height: height * factor
        )
    }
}

private extension CGRect {

    func rounded() -> CGRect {
        CGRect(
            x: origin.x.rounded(),
            y: origin.y.rounded(),
            width: width.rounded(),
            height: height.rounded()
        )
    }
}

private extension CGRect {

    func offset(_ dx: CGFloat, _ dy: CGFloat) -> CGRect {
        offsetBy(dx: dx, dy: dy)
    }
}

private extension CGRect {

    func containsEnoughArea() -> Bool {
        width > 20 && height > 20
    }
}

private extension CGRect {

    func normalized(in extent: CGRect) -> CGRect {
        CGRect(
            x: minX / extent.width,
            y: minY / extent.height,
            width: width / extent.width,
            height: height / extent.height
        )
    }
}

private extension CGRect {

    static func fromVision(_ rect: CGRect, imageExtent: CGRect) -> CGRect {
        CGRect(
            x: rect.minX * imageExtent.width,
            y: (1.0 - rect.maxY) * imageExtent.height,
            width: rect.width * imageExtent.width,
            height: rect.height * imageExtent.height
        )
    }
}

private extension CGRect {

    func integralRect() -> CGRect {
        integral
    }
}

private extension CGRect {

    func aspectRatio() -> CGFloat {
        width / height
    }
}

private extension CGRect {

    func padded(_ amount: CGFloat) -> CGRect {
        insetBy(dx: -amount, dy: -amount)
    }
}

private extension CGRect {

    func limited(to extent: CGRect) -> CGRect {
        intersection(extent)
    }
}

private extension CGRect {

    func translated(x: CGFloat, y: CGFloat) -> CGRect {
        offsetBy(dx: x, dy: y)
    }
}

private extension CGRect {

    func toVisionNormalized(imageExtent: CGRect) -> CGRect {
        CGRect(
            x: minX / imageExtent.width,
            y: minY / imageExtent.height,
            width: width / imageExtent.width,
            height: height / imageExtent.height
        )
    }
}

private extension CGRect {

    func rotated90() -> CGRect {
        CGRect(
            x: minY,
            y: minX,
            width: height,
            height: width
        )
    }
}

private extension CGRect {

    func area() -> CGFloat {
        width * height
    }
}

private extension CGRect {

    func squareDistance(to other: CGRect) -> CGFloat {

        let dx = midX - other.midX
        let dy = midY - other.midY

        return dx * dx + dy * dy
    }
}

private extension CGRect {

    func scaleAroundCenter(_ factor: CGFloat) -> CGRect {

        let newWidth = width * factor
        let newHeight = height * factor

        return CGRect(
            x: midX - newWidth / 2,
            y: midY - newHeight / 2,
            width: newWidth,
            height: newHeight
        )
    }
}

private extension CGRect {

    func pixelAligned() -> CGRect {
        integral
    }
}

private extension CGRect {

    func toImageSpace(_ imageExtent: CGRect) -> CGRect {
        CGRect.fromVision(self, imageExtent: imageExtent)
    }
}

private extension CGRect {

    func imageRect() -> CGRect {
        self
    }
}

private extension CGRect {

    func normalizedRect() -> CGRect {
        self
    }
}

private extension CGRect {

    func visionRect() -> CGRect {
        self
    }
}

private extension CGRect {

    func bounded(by rect: CGRect) -> CGRect {
        intersection(rect)
    }
}

private extension CGRect {

    func resized(width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(
            x: origin.x,
            y: origin.y,
            width: width,
            height: height
        )
    }
}

private extension CGRect {

    func moved(to point: CGPoint) -> CGRect {
        CGRect(origin: point, size: size)
    }
}

private extension CGRect {

    func cropped(to rect: CGRect) -> CGRect {
        intersection(rect)
    }
}

private extension CGRect {

    func toImageRect(_ imageExtent: CGRect) -> CGRect {
        CGRect(
            x: minX * imageExtent.width,
            y: (1 - maxY) * imageExtent.height,
            width: width * imageExtent.width,
            height: height * imageExtent.height
        )
    }
}
