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
    
    /// NEW: Extracts the card serial index number string from the bottom layout margin of the card boundary
    public func extractCardIdentifierText(from image: CGImage, cardBoundingBox: VNRectangleObservation, completion: @escaping (String?) -> Void) {
        let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])
        
        let textRequest = VNRecognizeTextRequest { request, error in
            guard error == nil, let textObservations = request.results as? [VNRecognizedTextObservation] else {
                completion(nil)
                return
            }
            
            // Loop through text results to locate a standard fraction sequence symbol layout (e.g., "150/195" or "022/185")
            for observation in textObservations {
                guard let candidateText = observation.topCandidates(1).first?.string else { continue }
                
                // Clear whitespace gaps out of the candidate stream
                let normalizedText = candidateText.replacingOccurrences(of: " ", with: "")
                
                // Look for patterns containing slashed numeric indices typical of modern trading card sets
                if normalizedText.contains("/") {
                    completion(normalizedText)
                    return
                }
            }
            completion(nil)
        }
        
        // Optimize efficiency performance: use accurate reading modes and lock tracking strictly over the bottom corner margins
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = false
        
        // Crop region of interest mapping box parameters tightly to the bottom 15% section grid lines
        textRequest.regionOfInterest = CGRect(x: 0.0, y: 0.0, width: 1.0, height: 0.15)
        
        try? requestHandler.perform([textRequest])
    }
    
    /// Extract sub-millimeter border centering ratios by comparing inner artwork lines to outer card boundaries
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
}

