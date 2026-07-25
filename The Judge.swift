import Foundation
import CoreGraphics

public struct DefectMarker: Identifiable {
    public let id = UUID()
    public let coordinateSpace: CGPoint
    public let opacityValue: Double
    public let flawType: String
}

import Foundation

public struct CalculatedGrade {
    public let finalScore: Double
    public let primaryFlawDescription: String
    public let isGemMint: Bool
}

public class TheJudge {
    
    public init() {}
    
    /// Evaluates compiled physical sub-metrics to award a unified condition score
    public func evaluateCardCondition(
        centering: CenteringResult,
        surfaceScratchesDetected: Int,
        edgeWhiteningCount: Int
    ) -> CalculatedGrade {
        
        var finalScore: Double = 10.0
        var mainFlaw = "None. Card exhibits flawless structure."
        
        if !centering.passesBGS10 {
            finalScore = min(finalScore, 9.5)
            mainFlaw = "Minor centering alignment offset detected."
        }
        if !centering.passesPSA10 {
            finalScore = min(finalScore, 9.0)
            mainFlaw = "Significant centering border skew detected."
        }
        
        if edgeWhiteningCount > 0 {
            finalScore -= (Double(edgeWhiteningCount) * 0.5)
            mainFlaw = "Visible edge whitening and paper friction wear."
        }
        
        if surfaceScratchesDetected > 0 {
            finalScore -= (Double(surfaceScratchesDetected) * 0.5)
            mainFlaw = "Micro-abrasions or surface layer scratches found."
        }
        
        finalScore = max(finalScore, 1.0)
        
        return CalculatedGrade(
            finalScore: finalScore,
            primaryFlawDescription: mainFlaw,
            isGemMint: finalScore >= 9.5
        )
    }
}
