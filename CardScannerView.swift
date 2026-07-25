import SwiftUI
import Charts 

struct CardScannerView: View {
    @StateObject private var calibrationEngine = CameraCalibration()
    @StateObject private var priceEngine = PricingEngine()
    @StateObject private var portfolio = PortfolioState()
    @StateObject private var securityVault = UserSecurity()
    
    // Core AI Analysis Engines
    private let gradingJudge = TheJudge()
    private let centeringAnalyzer = CenteringAnalyzer()
    private let defectAnalyzer = DefectAnalyzer()
    
    // Core state management parameters
    @State private var scanResult: CenteringResult?
    @State private var activeValuation: CardValuation?
    @State private var calculatedGrade: CalculatedGrade?
    @State private var isLoadingPrice: Bool = false
    @State private var isSaveConfirmed: Bool = false
    @State private var isCardDetected: Bool = false
    
    // Dynamic Damage Tuner Variables
    @State private var manualSurfaceScratches: Double = 0.0
    @State private var manualEdgeWhitening: Double = 0.0
    
    // Category Mode Active Selection Tracker
    @State private var selectedCategory: CardCategory = .tcg
    @State private var selectedTab: Int = 0
    
    // Search Filter Query Tracker
    @State private var searchVaultQuery: String = ""
    
    // Dynamically filter saved inventory records on the fly
    private var filteredVaultRecords: [SavedCard] {
        if searchVaultQuery.isEmpty {
            return portfolio.savedCards
        } else {
            return portfolio.savedCards.filter { card in
                card.name.localizedCaseInsensitiveContains(searchVaultQuery) ||
                card.setName.localizedCaseInsensitiveContains(searchVaultQuery)
            }
        }
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            
            // ==================== TAB 1: THE SCANNING DASHBOARD ====================
            NavigationView {
                ScrollView {
                    VStack(spacing: 20) {
                        
                        // Category Selector Configuration Header
                        VStack(alignment: .leading, spacing: 6) {
                            Text("ACTIVE TARGET PROFILES")
                                .font(.caption2).bold().foregroundColor(.secondary)
                                .padding(.horizontal)
                            
                            Picker("Card Profile", selection: $selectedCategory) {
                                ForEach(CardCategory.allCases) { category in
                                    Text(category.rawValue).tag(category)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal)
                            .onChange(of: selectedCategory) {
                                resetCurrentScanState()
                            }
                        }
                        .padding(.top, 5)
                        
                        // 1. Live Interactive Scanner Window Area with Dynamic Heatmaps
                        ZStack {
                            LiveCameraView { rawCapturedFrame in
                                processLiveCameraFrame(rawCapturedFrame)
                            }
                            .environmentObject(calibrationEngine)
                            .frame(height: 240)
                            .cornerRadius(12)
                            .clipped()
                            
                            // Standard Target Bounding Box Frame
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(isCardDetected ? Color.green : Color.white.opacity(0.4), lineWidth: isCardDetected ? 4 : 2)
                                .frame(width: 170, height: 210)
                                .overlay(
                                    ZStack {
                                        if !isCardDetected {
                                            VStack {
                                                Image(systemName: "viewfinder")
                                                    .font(.title2)
                                                    .foregroundColor(.white)
                                                Text("ALIGN CARD")
                                                    .font(.caption2).bold()
                                                    .foregroundColor(.white)
                                                    .padding(4)
                                                    .background(Color.black.opacity(0.6))
                                                    .cornerRadius(4)
                                            }
                                        }
                                        
                                        // Active Lab Centering Crosshairs & Matrix Percentage Indicators
                                        if isCardDetected, let centeringRatio = scanResult {
                                            CenteringGuideOverlay(ratios: centeringRatio)
                                        }
                                        
                                        // Live Surface Micro-Scratch Heatmap Markers
                                        if manualSurfaceScratches >= 1.0 {
                                            Circle()
                                                .stroke(Color.red, lineWidth: 2)
                                                .frame(width: 30, height: 30)
                                                .background(Circle().fill(Color.red.opacity(0.25)))
                                                .position(x: 60, y: 90)
                                                .transition(.scale)
                                        }
                                        if manualSurfaceScratches >= 3.0 {
                                            Circle()
                                                .stroke(Color.red, lineWidth: 2)
                                                .frame(width: 40, height: 40)
                                                .background(Circle().fill(Color.red.opacity(0.25)))
                                                .position(x: 120, y: 130)
                                                .transition(.scale)
                                        }
                                        
                                        // Live Edge Whitening Friction Wear Heatmap Markers
                                        if manualEdgeWhitening >= 1.0 {
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(Color.red, lineWidth: 2)
                                                .frame(width: 15, height: 15)
                                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.red.opacity(0.3)))
                                                .position(x: 10, y: 15)
                                                .transition(.opacity)
                                        }
                                        if manualEdgeWhitening >= 2.0 {
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(Color.red, lineWidth: 2)
                                                .frame(width: 15, height: 15)
                                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.red.opacity(0.3)))
                                                .position(x: 160, y: 195)
                                                .transition(.opacity)
                                        }
                                    }
                                )
                            
                            VStack {
                                ZStack {
                                    Circle()
                                        .stroke(calibrationEngine.isPerfectlyLevel ? Color.green : Color.red, lineWidth: 3)
                                        .frame(width: 45, height: 45)
                                    
                                    Circle()
                                        .fill(calibrationEngine.isPerfectlyLevel ? Color.green : Color.orange)
                                        .frame(width: 10, height: 10)
                                        .offset(
                                            x: CGFloat(calibrationEngine.currentRoll * 4),
                                            y: CGFloat(calibrationEngine.currentPitch * 4)
                                        )
                                        .animation(.interactiveSpring(), value: calibrationEngine.currentRoll)
                                }
                                Spacer()
                            }
                            .padding(.top, 10)
                        }
                        .padding(.horizontal)
                        
                        // 2. Dynamic Gem Mint Eligibility Warnings
                        if manualSurfaceScratches > 0 || manualEdgeWhitening > 0 {
                            VStack(alignment: .leading, spacing: 6) {
                                ios_warning_fix()
                            }
                            .padding(10)
                            .background(Color.red.opacity(0.08))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.3), lineWidth: 1))
                            .padding(.horizontal)
                        }
                        
                        // 3. Interactive Damage Tuning Mixer
                        VStack(alignment: .leading, spacing: 12) {
                            Text("MANUAL DEFECT TUNING MIXER").font(.caption).bold().foregroundColor(.secondary)
                            VStack(spacing: 10) {
                                child_slider_surface_layer()
                                child_slider_edge_layer()
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                        // 4. Shutter Trigger Button
                        Button(action: {
                            withAnimation { isCardDetected = true }
                            executeGradingPipeline()
                        }) {
                            Text("Run Live AI Calibration & Grade")
                                .bold()
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(calibrationEngine.isPerfectlyLevel ? Color.blue : Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .disabled(!calibrationEngine.isPerfectlyLevel)
                        .padding(.horizontal)
                        // 5. Main Grade Analysis Output Report
                        if isLoadingPrice {
                            ProgressView("Analyzing Alignment & Market Values...").padding()
                        } else if let result = scanResult, let value = activeValuation, let grade = calculatedGrade {
                            VStack(alignment: .leading, spacing: 15) {
                                Text("AI COMPLIANCE GRADE REPORT").font(.caption).bold().foregroundColor(.secondary)
                                ZionHStackRow(result: result, grade: grade, value: value)
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
                .navigationTitle("AI Grade Scanner")
                .onAppear {
                    calibrationEngine.startDeviceLevelMonitoring()
                    let diagnosticSuite = TheJudgeTests()
                    diagnosticSuite.runAllGradingTests()
                }
                .onDisappear {
                    calibrationEngine.stopDeviceLevelMonitoring()
                }
            }
            .tabItem {
                Label("Scanner", systemImage: "viewfinder.lens")
            }
            .tag(0)
            // ==================== TAB 2: PORTFOLIO VAULT ANALYTICS ====================
            NavigationView {
                VStack(spacing: 0) {
                    if !securityVault.isVaultUnlocked {
                        ScrollView {
                            VStack(spacing: 12) {
                                Image(systemName: "lock.shield.fill").font(.largeTitle).foregroundColor(.blue)
                                Text("Analytics Vault Encrypted").font(.headline)
                                Text("Verify identity to inspect vault performance and asset allocations safely.").font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                                Button("Verify Biometrics") { securityVault.authenticateCollectorVault() }
                                    .bold().foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 12).background(Color.blue).cornerRadius(8).padding(.horizontal)
                            }
                            .padding(.vertical, 40)
                            .frame(maxWidth: .infinity)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                            .padding(.horizontal).padding(.top, 40)
                        }
                    } else {
                        // Dynamic Financial Header Banner
                        HStack(spacing: 15) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("NET WORTH").font(.caption2).bold().foregroundColor(.secondary)
                                Text(String(format: "$%.2f", portfolio.totalPortfolioValue)).font(.title2).bold().foregroundColor(.blue)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding().background(Color(.secondarySystemBackground))
                            .cornerRadius(10)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("VAULT COUNT").font(.caption2).bold().foregroundColor(.secondary)
                                Text("(portfolio.savedCards.count) Cards").font(.title2).bold().foregroundColor(.purple)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding().background(Color(.secondarySystemBackground))
                            .cornerRadius(10)
                        }
                        .padding(.horizontal)
                        .padding(.top, 10)
                        if portfolio.totalPortfolioValue > 0 {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("HISTORICAL VALUATION TRACK").font(.caption2).bold().foregroundColor(.secondary)
                                    Spacer()
                                    Button(action: {
                                        if let printedDocumentURL = portfolio.generatePrintableSubmissionManifest() {
                                            let activityControllerWindow = UIActivityViewController(activityItems: [printedDocumentURL], applicationActivities: nil)
                                            if let topmostPresentedViewController = UIApplication.shared.connectedScenes
                                                .flatMap({ ($0 as? UIWindowScene)?.windows ?? [] })
                                                .first(where: { $0.isKeyWindow })?.rootViewController {
                                                activityControllerWindow.popoverPresentationController?.sourceView = topmostPresentedViewController.view
                                                activityControllerWindow.popoverPresentationController?.sourceRect = CGRect(x: topmostPresentedViewController.view.bounds.width / 2, y: topmostPresentedViewController.view.bounds.height / 2, width: 0, height: 0)
                                                activityControllerWindow.popoverPresentationController?.permittedArrowDirections = []
                                                topmostPresentedViewController.present(activityControllerWindow, animated: true, completion: nil)
                                            }
                                        }
                                    }) {
                                        Label("Export PDF Manifest", systemImage: "doc.badge.gearshape.fill").font(.caption2).bold().foregroundColor(.blue)
                                    }
                                }
                                .padding(.horizontal)
                                Chart {
                                    ForEach(portfolio.historicalTrendSnapshots) { snapshot in
                                        AreaMark(x: .value("Timeline", snapshot.date, unit: .day), y: .value("Net Worth", snapshot.value))
                                            .foregroundStyle(Gradient(colors: [Color.blue.opacity(0.25), Color.blue.opacity(0.01)]))
                                        LineMark(x: .value("Timeline", snapshot.date, unit: .day), y: .value("Net Worth", snapshot.value))
                                            .foregroundStyle(Color.blue).lineStyle(StrokeStyle(lineWidth: 3))
                                    }
                                }
                                .frame(height: 120).padding(.all, 12).background(Color(.secondarySystemBackground)).cornerRadius(12).padding(.horizontal)
                            }
                            .padding(.top, 10)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text("VAULT RECORDS LEDGER").font(.caption2).bold().foregroundColor(.secondary).padding(.horizontal).padding(.top, 15)
                            if portfolio.savedCards.isEmpty {
                                Text("No cards saved inside vault archives yet.").font(.footnote).foregroundColor(.secondary).padding(.horizontal)
                                Spacer()
                            } else {
                                List {
                                    ForEach(filteredVaultRecords) { card in
                                        HStack {
                                            VStack(alignment: .leading) {
                                                Text(card.name).font(.subheadline).bold().lineLimit(1)
                                                Text(card.setName).font(.caption).foregroundColor(.secondary)
                                            }
                                            Spacer()
                                            VStack(alignment: .trailing) {
                                                Text(String(format: "$%.2f", card.calculatedValue)).font(.subheadline).bold().foregroundColor(.green)
                                                Text("PSA (card.predictedGradePSA)").font(.caption2).padding(4).background(Color.blue.opacity(0.1)).cornerRadius(4)
                                            }
                                        }
                                        .listRowBackground(Color(.secondarySystemBackground))
                                    }
                                    .onDelete { structuralIndexSet in
                                        portfolio.deleteCard(at: structuralIndexSet)
                                    }
                                }
                                .listStyle(.plain)
                                .cornerRadius(12)
                                .padding(.horizontal)
                            }
                        }
                    }
                }
                .navigationTitle("Vault Analytics")
                .searchable(text: $searchVaultQuery, placement: .navigationBarDrawer, prompt: "Search Name or Expansion Set...")
            }
            .tabItem {
                Label("Vault", systemImage: "chart.pie.fill")
            }
            .tag(1)
        }
    }
    // View helper layers to optimize complex layout chains inside Playgrounds
    @ViewBuilder
    private func ios_warning_fix() -> some View {
        HStack {
            Image(systemName: "exclamationmark.shield.fill").foregroundColor(.red)
            Text("GEM MINT ELIGIBILITY BREAKDOWN").font(.caption2).bold().foregroundColor(.red)
            Spacer()
        }
        if manualSurfaceScratches >= 1.0 { Text("• Surface micro-scratches invalidate pristine requirements.").font(.caption2).foregroundColor(.secondary) }
        if manualEdgeWhitening >= 1.0 { Text("• Edge whitening scuffs break strict sub-grade tolerances.").font(.caption2).foregroundColor(.secondary) }
    }
    @ViewBuilder
    private func child_slider_surface_layer() -> some View {
        HStack {
            Image(systemName: "sparkles").foregroundColor(.purple)
            Text("Surface Micro-Scratches: (Int(manualSurfaceScratches))").font(.subheadline)
            Spacer()
        }
        Slider(value: $manualSurfaceScratches, in: 0...5, step: 1.0) { _ in recomputeLiveGradeFromTuner() }.accentColor(.purple)
    }
    @ViewBuilder
    private func child_slider_edge_layer() -> some View {
        HStack {
            Image(systemName: "bandage.fill").foregroundColor(.orange)
            Text("Edge Whitening Scuffs: (Int(manualEdgeWhitening))").font(.subheadline)
            Spacer()
        }
        Slider(value: $manualEdgeWhitening, in: 0...5, step: 1.0) { _ in recomputeLiveGradeFromTuner() }.accentColor(.orange)
    }
    // Active Centering Calibration Guidelines Overlay Crosshairs
    @ViewBuilder
    private func CenteringGuideOverlay(ratios: CenteringResult) -> some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 105))
                path.addLine(to: CGPoint(x: 170, y: 105))
            }
            .stroke(Color.blue.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            Path { path in
                path.move(to: CGPoint(x: 85, y: 0))
                path.addLine(to: CGPoint(x: 85, y: 210))
            }
            .stroke(Color.blue.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            VStack {
                HStack {
                    Text(String(format: "L:%.0f%%", ratios.leftRightRatio.left))
                    Spacer()
                    Text(String(format: "R:%.0f%%", ratios.leftRightRatio.right))
                }
                Spacer()
                HStack {
                    Text(String(format: "T:%.0f%%", ratios.topBottomRatio.top))
                    Spacer()
                    Text(String(format: "B:%.0f%%", ratios.topBottomRatio.bottom))
                }
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(.green)
            .padding(6)
        }
        .frame(width: 170, height: 210)
    }
    @ViewBuilder
    private func ZionHStackRow(result: CenteringResult, grade: CalculatedGrade, value: CardValuation) -> some View {
        HStack {
            Text("Calculated Condition:")
            Spacer()
            let strictGradeResult = selectedCategory == .sports && !result.passesBGS10 ? max(1.0, grade.finalScore - 0.5) : grade.finalScore
            Text(String(format: "PRE-GRADE %.1f", strictGradeResult))
                .font(.title2).bold()
                .foregroundColor(strictGradeResult >= 9.5 ? .green : .blue)
        }
        Text(grade.primaryFlawDescription).font(.caption).foregroundColor(.secondary).italic()
        Divider()
        HStack {
            Text("Dynamic Value Projection:")
            Spacer()
            let strictGradeResult = selectedCategory == .sports && !result.passesBGS10 ? max(1.0, grade.finalScore - 0.5) : grade.finalScore
            let dynamicValueMultiplier = max(0.1, (strictGradeResult / 10.0))
            let dynamicallyAdjustedPrice = (selectedCategory == .sports ? 185.00 : value.marketValuePSA10) * dynamicValueMultiplier
            Text(String(format: "$%.2f", dynamicallyAdjustedPrice)).bold().foregroundColor(.green)
        }
        Divider()
        Button(action: {
            let strictGradeResult = selectedCategory == .sports && !result.passesBGS10 ? max(1.0, grade.finalScore - 0.5) : grade.finalScore
            let dynamicValueMultiplier = max(0.1, (strictGradeResult / 10.0))
            portfolio.appendCard(
                name: selectedCategory == .sports ? "Michael Jordan Rookie Reprint" : value.cardName,
                set: selectedCategory == .sports ? "Fleer Retro (2012)" : value.setName,
                lrCentering: String(format: "%.1f%% / %.1f%%", result.leftRightRatio.left, result.leftRightRatio.right),
                tbCentering: String(format: "%.1f%% / %.1f%%", result.topBottomRatio.top, result.topBottomRatio.bottom),
                predictedGrade: Int(strictGradeResult),
                marketValue: (selectedCategory == .sports ? 185.00 : value.marketValuePSA10) * dynamicValueMultiplier
            )
            withAnimation { isSaveConfirmed = true }
        }) {
            Label(isSaveConfirmed ? "Saved to Portfolio Vault" : "Commit Scan to Collection Portfolio", systemImage: isSaveConfirmed ? "checkmark.seal.fill" : "folder.badge.plus")
                .bold()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isSaveConfirmed ? Color.green : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
        }
        .disabled(isSaveConfirmed)
    }
    // MARK: - Core Execution Functions
    private func executeGradingPipeline() {
        self.isSaveConfirmed = false
        calibrationEngine.playSuccessChirp()
        if scanResult == nil {
            let testCentering = CenteringResult(leftRightRatio: (51.2, 48.8), topBottomRatio: (49.5, 50.5), passesPSA10: true, passesBGS10: true)
            self.scanResult = testCentering
        }
        guard let validCentering = scanResult else { return }
        self.calculatedGrade = gradingJudge.evaluateCardCondition(
            centering: validCentering,
            surfaceScratchesDetected: Int(manualSurfaceScratches),
            edgeWhiteningCount: Int(manualEdgeWhitening)
        )
        self.isLoadingPrice = true
        priceEngine.fetchLiveValuations(cardId: selectedCategory == .sports ? "jordan-fleer-92" : "charizard-base-1st") { result in
            self.isLoadingPrice = false
            if case .success(let data) = result { self.activeValuation = data }
        }
    }
    private func recomputeLiveGradeFromTuner() {
        guard let currentCentering = scanResult else { return }
        self.isSaveConfirmed = false
        self.calculatedGrade = gradingJudge.evaluateCardCondition(centering: currentCentering, surfaceScratchesDetected: Int(manualSurfaceScratches), edgeWhiteningCount: Int(manualEdgeWhitening))
    }
    private func resetCurrentScanState() {
        self.scanResult = nil
        self.activeValuation = nil
        self.calculatedGrade = nil
        self.isSaveConfirmed = false
        self.isCardDetected = false
        self.manualSurfaceScratches = 0.0
        self.manualEdgeWhitening = 0.0
    }
    // MARK: - Automated AI Hardware Pipeline Connector
    private func processLiveCameraFrame(_ imageFrame: CGImage) {
        guard !isLoadingPrice && !isSaveConfirmed else { return }
        centeringAnalyzer.detectCardRectangle(in: imageFrame) { recognizedObservation in
            guard let cardRect = recognizedObservation else {
                if self.isCardDetected { self.isCardDetected = false }
                return
            }
            if !self.isCardDetected { self.isCardDetected = true }
            let computedCentering = centeringAnalyzer.analyzeCentering(from: cardRect)
            let automatedDefects = defectAnalyzer.analyzeCardSurface(from: imageFrame)
            DispatchQueue.main.async {
                self.scanResult = computedCentering
                self.manualSurfaceScratches = Double(automatedDefects.surfaceScratchCount)
                self.manualEdgeWhitening = Double(automatedDefects.edgeWhiteningSeverity)
                self.calculatedGrade = gradingJudge.evaluateCardCondition(
                    centering: computedCentering,
                    surfaceScratchesDetected: automatedDefects.surfaceScratchCount,
                    edgeWhiteningCount: automatedDefects.edgeWhiteningSeverity
                )
            }
        }
    }
}

