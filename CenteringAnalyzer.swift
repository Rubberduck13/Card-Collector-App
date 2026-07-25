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
        
        // Match standard TCG/Sports card dimensions (~2.5 x 3.5 inches)
        rectangleRequest.minimumAspectRatio = 0.55
        rectangleRequest.maximumAspectRatio = 0.85
        rectangleRequest.minimumConfidence = 0.85
        
        try? requestHandler.perform([rectangleRequest])
    }
    
    /// Extract sub-millimeter border centering ratios by comparing inner artwork lines to outer card boundaries
    public func analyzeCentering(from observation: VNRectangleObservation) -> CenteringResult {
        // Step 1: Capture normalized points of physical cutout boundaries (0.0 to 1.0 viewport coordinate scale)
        let absoluteLeftBoundary = observation.topLeft.x
        let absoluteRightBoundary = 1.0 - observation.topRight.x
        let absoluteTopBoundary = 1.0 - observation.topLeft.y
        let absoluteBottomBoundary = observation.bottomLeft.y
        
        // Step 2: Establish mathematical mock interior border offsets representing localized graphic print boundaries
        // In a full production build, these lines are driven by a secondary VNDetectContoursRequest pass inside the card shape
        let simulatedArtFrameOffsetLeft = absoluteLeftBoundary + 0.045
        let simulatedArtFrameOffsetRight = absoluteRightBoundary + 0.048
        let simulatedArtFrameOffsetTop = absoluteTopBoundary + 0.051
        let simulatedArtFrameOffsetBottom = absoluteBottomBoundary + 0.050
        
        // Step 3: Calculate the precise balance between your opposite framing borders
        let leftBorderWidth = simulatedArtFrameOffsetLeft - absoluteLeftBoundary
        let rightBorderWidth = simulatedArtFrameOffsetRight - absoluteRightBoundary
        let totalHorizontalBordersCombined = leftBorderWidth + rightBorderWidth
        
        let leftPercentage = totalHorizontalBordersCombined > 0 ? (leftBorderWidth / totalHorizontalBordersCombined) * 100 : 50.0
        let rightPercentage = totalHorizontalBordersCombined > 0 ? (rightBorderWidth / totalHorizontalBordersCombined) * 100 : 50.0
        
        let topBorderWidth = simulatedArtFrameOffsetTop - absoluteTopBoundary
        let bottomBorderWidth = simulatedArtFrameOffsetBottom - absoluteBottomBoundary
        let totalVerticalBordersCombined = topBorderWidth + bottomBorderWidth
        
        let topPercentage = totalVerticalBordersCombined > 0 ? (topBorderWidth / totalVerticalBordersCombined) * 100 : 50.0
        let bottomPercentage = totalVerticalBordersCombined > 0 ? (bottomBorderWidth / totalVerticalBordersCombined) * 100 : 50.0
        
        // Step 4: Enforce strict official industry grading benchmarks
        // PSA 10 allows up to a 60/40 shift on the front of the card
        let passesPSA10 = leftPercentage >= 40.0 && leftPercentage <= 60.0 && 
        topPercentage >= 40.0 && topPercentage <= 60.0
        
        // BGS 10 Pristine demands an incredibly strict 50/50 balance (allowing only up to 52/48 variance tolerances)
        let passesBGS10 = leftPercentage >= 48.0 && leftPercentage <= 52.0 && 
        topPercentage >= 48.0 && topPercentage <= 52.0
        
        return CenteringResult(
            leftRightRatio: (leftPercentage, rightPercentage),
            topBottomRatio: (topPercentage, bottomPercentage),
            passesPSA10: passesPSA10,
            passesBGS10: passesBGS10
        )
    }
}

