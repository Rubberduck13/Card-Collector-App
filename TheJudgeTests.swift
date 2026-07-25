import Foundation

public final class TheJudgeTests {
    
    private let sut = TheJudge()
    
    public init() {}
    
    /// Executes the entire grading suite and prints assertions directly to the diagnostics log
    public func runAllGradingTests() {
        print("====== STARTING AUTOMATED GRADING SUITE ASSERTIONS ======")
        
        testEvaluateCardCondition_WithPerfectMetrics_ReturnsAbsoluteTen()
        testEvaluateCardCondition_WithCombinedDefects_CalculatesCompoundDeductions()
        testEvaluateCardCondition_WithSevereCenteringMisalignment_CapsBaseAtNine()
        testEvaluateCardCondition_WithCatastrophicDamage_MaintainsFloorLimit()
        testEvaluateCardCondition_WithDominantPhysicalDamage_OverridesCenteringCaps()
        
        print("====== AUTOMATED GRADING SUITE TASKS COMPLETED ======")
    }
    
    // MARK: - 1. Flawless Black Label Validation Pass
    private func testEvaluateCardCondition_WithPerfectMetrics_ReturnsAbsoluteTen() {
        let perfectCentering = CenteringResult(
            leftRightRatio: (50.0, 50.0),
            topBottomRatio: (50.0, 50.0),
            passesPSA10: true,
            passesBGS10: true
        )
        
        let report = sut.evaluateCardCondition(centering: perfectCentering, surfaceScratchesDetected: 0, edgeWhiteningCount: 0)
        
        assert(report.finalScore == 10.0, "❌ FAILED: Flawless metrics must yield an absolute 10.0 card grade.")
        assert(report.isGemMint == true, "❌ FAILED: A perfect card must pass Gem Mint validation restrictions.")
        print("✅ PASSED: Perfect Pristine 10.0 Validation Engine Match.")
    }
    
    // MARK: - 2. Complex Multi-Defect Accumulation Test
    private func testEvaluateCardCondition_WithCombinedDefects_CalculatesCompoundDeductions() {
        let minorSkewCentering = CenteringResult(
            leftRightRatio: (46.0, 54.0),
            topBottomRatio: (50.0, 50.0),
            passesPSA10: true,
            passesBGS10: false
        )
        
        let report = sut.evaluateCardCondition(centering: minorSkewCentering, surfaceScratchesDetected: 1, edgeWhiteningCount: 2)
        
        assert(report.finalScore == 8.0, "❌ FAILED: Compound defects must deduct subtractively from the initial alignment cap.")
        assert(report.isGemMint == false, "❌ FAILED: Accumulated defects must automatically invalidate Gem Mint compliance gates.")
        print("✅ PASSED: Compound Multi-Defect Accumulation Scoring Match.")
    }
    
    // MARK: - 3. Extreme Outer Centering Skew Test
    private func testEvaluateCardCondition_WithSevereCenteringMisalignment_CapsBaseAtNine() {
        let severeSkewCentering = CenteringResult(
            leftRightRatio: (35.0, 65.0),
            topBottomRatio: (50.0, 50.0),
            passesPSA10: false,
            passesBGS10: false
        )
        
        let report = sut.evaluateCardCondition(centering: severeSkewCentering, surfaceScratchesDetected: 0, edgeWhiteningCount: 0)
        
        assert(report.finalScore == 9.0, "❌ FAILED: Severe border alignment skews must cap the maximum allowable grade at a flat 9.0.")
        print("✅ PASSED: Severe Centering Edge Misalignment Cap Match.")
    }
    
    // MARK: - 4. Maximum Limit Damage Threshold Test
    private func testEvaluateCardCondition_WithCatastrophicDamage_MaintainsFloorLimit() {
        let terribleCentering = CenteringResult(
            leftRightRatio: (30.0, 70.0),
            topBottomRatio: (25.0, 75.0),
            passesPSA10: false,
            passesBGS10: false
        )
        
        let report = sut.evaluateCardCondition(centering: terribleCentering, surfaceScratchesDetected: 12, edgeWhiteningCount: 15)
        
        assert(report.finalScore == 1.0, "❌ FAILED: The grading score must never drop below the standard laboratory floor limit of 1.0.")
        print("✅ PASSED: Catastrophic Lower Boundary Limit Floor Match.")
    }
    
    // MARK: - 5. Sub-Grade Hierarchy Constraint Test
    private func testEvaluateCardCondition_WithDominantPhysicalDamage_OverridesCenteringCaps() {
        let perfectCentering = CenteringResult(
            leftRightRatio: (50.0, 50.0),
            topBottomRatio: (50.0, 50.0),
            passesPSA10: true,
            passesBGS10: true
        )
        
        let report = sut.evaluateCardCondition(centering: perfectCentering, surfaceScratchesDetected: 0, edgeWhiteningCount: 8)
        
        assert(report.finalScore == 6.0, "❌ FAILED: Severe localized structural wear must cleanly override pristine centering scores.")
        print("✅ PASSED: Physical Damage Sub-Grade Hierarchy Override Match.")
    }
}

