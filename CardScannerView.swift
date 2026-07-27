import SwiftUI
import Charts 

struct CategoryAllocation: Identifiable {
    let id = UUID()
    let categoryName: String
    let totalValue: Double
    let accentColor: Color
}

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
    
    // Live Vision OCR Card Identifier Parameter String Tracker
    @State private var automaticCardIdentifier: String = "Scanning..."
    
    // Dynamic Damage Tuner Variables
    @State private var manualSurfaceScratches: Double = 0.0
    @State private var manualEdgeWhitening: Double = 0.0
    
    // Category Mode Active Selection Tracker
    @State private var selectedCategory: CardCategory = .tcg
    @State private var selectedTab: Int = 0
    
    // Search Filter Query Tracker
    @State private var searchVaultQuery: String = ""
    
    // Interactive Multi-Batch UI State Parameters
    @State private var selectedBatchFolderId: UUID? = nil
    @State private var newBatchInputName: String = ""
    @State private var newBatchServiceSelection: String = "PSA"
    @State private var isBatchExporting: Bool = false
    
    // Lab Simulation Target Selection Parameters
    @State private var selectedSimulatorCompany: String = "PSA"
    @State private var highlightedSimulationCard: SavedCard? = nil
    
    // Arbitrage Tab Card Selection Tracker
    @State private var selectedArbitrageCard: SavedCard? = nil
    
    // Ticker History Selection Card Parameter Tracker
    @State private var selectedTickerCard: SavedCard? = nil
    
    // Passport Tab Selected Batch Tracker
    @State private var passportSelectedBatchId: UUID? = nil
    
    // Active Monitor Selected Item Target State Tracker
    @State private var selectedMonitorCard: SavedCard? = nil
    
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
    
    private var batchSegmentedCardRecords: [SavedCard] {
        guard let targetedId = selectedBatchFolderId else { return portfolio.savedCards }
        return portfolio.savedCards.filter { $0.targetBatchId == targetedId }
    }
    
    private var portfolioCategoryAllocations: [CategoryAllocation] {
        let baseCards = portfolio.savedCards
        let baseValue = portfolio.totalPortfolioValue
        
        let tcgSum: Double = baseCards.reduce(0.0) { runningTotal, currentCard in 
            runningTotal + currentCard.calculatedValue 
        }
        
        let initialTcgTotal: Double = tcgSum > 0.0 ? tcgSum : 1.0
        let calculatedSportsTotal: Double = baseValue > 0.0 ? baseValue * 0.35 : 0.0
        let calculatedMtgTotal: Double = baseValue > 0.0 ? baseValue * 0.15 : 0.0
        
        let tcgItem = CategoryAllocation(categoryName: "TCG / Pokémon", totalValue: initialTcgTotal, accentColor: .blue)
        let sportsItem = CategoryAllocation(categoryName: "Sports", totalValue: calculatedSportsTotal, accentColor: .purple)
        let mtgItem = CategoryAllocation(categoryName: "Magic / MTG", totalValue: calculatedMtgTotal, accentColor: .orange)
        
        return [tcgItem, sportsItem, mtgItem]
    }
    
    // MARK: - Main Tab Switcher Router
    var body: some View {
        TabView(selection: $selectedTab) {
            scannerDashboardView
                .tabItem { Label("Scanner", systemImage: "viewfinder.lens") }
                .tag(0)
            
            vaultAnalyticsView
                .tabItem { Label("Vault", systemImage: "chart.pie.fill") }
                .tag(1)
            
            bulkBatchManifestView
                .tabItem { Label("Bulk Ship", systemImage: "shippingbox.fill") }
                .tag(2)
            
            labSimulatorView
                .tabItem { Label("Lab Sim", systemImage: "waveform.path.ecg.rectangle.fill") }
                .tag(3)
            
            arbitrageMatrixView
                .tabItem { Label("ROI Matrix", systemImage: "dollarsign.circle.fill") }
                .tag(4)
            
            liveMarketTickerView
                .tabItem { Label("Ticker", systemImage: "chart.xyaxis.line") }
                .tag(5)
            
            labPassportManifestView
                .tabItem { Label("Passport", systemImage: "qrcode") }
                .tag(6)
            
            activeMarketplaceMonitorView
                .tabItem { Label("Live Deals", systemImage: "cart.badge.plus") }
                .tag(7)
        }
        .onAppear {
            if selectedBatchFolderId == nil, let initialBatch = portfolio.activeSubmissionBatches.first {
                selectedBatchFolderId = initialBatch.id
            }
            if passportSelectedBatchId == nil, let initialBatch = portfolio.activeSubmissionBatches.first {
                passportSelectedBatchId = initialBatch.id
            }
            if selectedArbitrageCard == nil, let initialCard = portfolio.savedCards.first {
                selectedArbitrageCard = initialCard
            }
            if selectedTickerCard == nil, let initialCard = portfolio.savedCards.first {
                selectedTickerCard = initialCard
            }
            if selectedMonitorCard == nil, let initialCard = portfolio.savedCards.first {
                selectedMonitorCard = initialCard
            }
        }
    }
    
    // MARK: - Sub-View 1: Scanner Dashboard Target Container
    private var scannerDashboardView: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
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
                    
                    cameraViewportSection
                    
                    HStack {
                        Image(systemName: "text.magnifyingglass")
                            .foregroundColor(.blue)
                        Text("AUTO-IDENTIFIED SERIAL INDEX: ")
                            .font(.caption2).bold()
                            .foregroundColor(.secondary)
                        Text(automaticCardIdentifier)
                            .font(.caption2).bold()
                            .foregroundColor(.blue)
                        Spacer()
                    }
                    .padding(.horizontal)
                    
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
    }
    // MARK: - Sub-View 2: Visual Camera Target Viewport
    private var cameraViewportSection: some View {
        ZStack {
            LiveCameraView { rawCapturedFrame in
                processLiveCameraFrame(rawCapturedFrame)
            }
            .environmentObject(calibrationEngine)
            .frame(height: 240)
            .cornerRadius(12)
            .clipped()
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
                        if isCardDetected, let centeringRatio = scanResult {
                            CenteringGuideOverlay(ratios: centeringRatio)
                        }
                        if manualSurfaceScratches >= 1.0 {
                            Circle()
                                .stroke(Color.red, lineWidth: 2)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(Color.red.opacity(0.25)))
                                .position(x: 60, y: 90)
                        }
                        if manualSurfaceScratches >= 3.0 {
                            Circle()
                                .stroke(Color.red, lineWidth: 2)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(Color.red.opacity(0.25)))
                                .position(x: 120, y: 130)
                        }
                        if manualEdgeWhitening >= 1.0 {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.red, lineWidth: 2)
                                .frame(width: 15, height: 15)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.red.opacity(0.3)))
                                .position(x: 10, y: 15)
                        }
                        if manualEdgeWhitening >= 2.0 {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.red, lineWidth: 2)
                                .frame(width: 15, height: 15)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.red.opacity(0.3)))
                                .position(x: 160, y: 195)
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
                }
                Spacer()
            }
            .padding(.top, 10)
        }
        .padding(.horizontal)
    }
    // MARK: - Sub-View 3: Secure Vault Analytics Target Container
    private var vaultAnalyticsView: some View {
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
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 15) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("HISTORICAL VALUATION TRACK").font(.caption2).bold().foregroundColor(.secondary)
                                        Spacer()
                                        ExportManifestButton()
                                    }
                                    Chart {
                                        ForEach(portfolio.historicalTrendSnapshots) { snapshot in
                                            AreaMark(x: .value("Timeline", snapshot.date), y: .value("Net Worth", snapshot.value))
                                                .foregroundStyle(Color.blue.opacity(0.15))
                                            LineMark(x: .value("Timeline", snapshot.date), y: .value("Net Worth", snapshot.value))
                                                .foregroundStyle(Color.blue)
                                        }
                                    }
                                    .frame(width: 250, height: 110)
                                }
                                .padding(.all, 12).background(Color(.secondarySystemBackground)).cornerRadius(12)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("VAULT DIVERSITY SECTOR ALLOCATION").font(.caption2).bold().foregroundColor(.secondary)
                                    Chart {
                                        ForEach(portfolioCategoryAllocations) { allocation in
                                            SectorMark(
                                                angle: .value("Value", allocation.totalValue),
                                                innerRadius: .ratio(0.6)
                                            )
                                            .foregroundStyle(allocation.accentColor)
                                        }
                                    }
                                    .frame(width: 250, height: 110)
                                }
                                .padding(.all, 12).background(Color(.secondarySystemBackground)).cornerRadius(12)
                            }
                            .padding(.horizontal)
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
                                ForEach(portfolio.savedCards) { card in
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
                            }
                            .listStyle(.plain)
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                    }
                }
            }
        }
    }
    // MARK: - Sub-View 4: Advanced Logistics Bulk Multi-Folder Dashboard Staging Area
    private var bulkBatchManifestView: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(portfolio.activeSubmissionBatches) { folder in
                            Button(action: {
                                selectedBatchFolderId = folder.id
                            }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Image(systemName: "folder.fill")
                                            .foregroundColor(selectedBatchFolderId == folder.id ? .white : .blue)
                                        Spacer()
                                        Text(folder.gradingServiceTarget)
                                            .font(.system(size: 8, weight: .black))
                                            .padding(3)
                                            .background(Color.white.opacity(0.2))
                                            .cornerRadius(4)
                                    }
                                    Text(folder.batchName)
                                        .font(.caption).bold()
                                        .lineLimit(1)
                                    Text("(portfolio.savedCards.filter { $0.targetBatchId == folder.id }.count) cards inside")
                                        .font(.system(size: 9))
                                        .opacity(0.8)
                                }
                                .foregroundColor(selectedBatchFolderId == folder.id ? .white : .primary)
                                .padding(12)
                                .frame(width: 150, height: 75)
                                .background(selectedBatchFolderId == folder.id ? Color.blue : Color(.secondarySystemBackground))
                                .cornerRadius(12)
                            }
                        }
                    }
                    .padding()
                }
                Form {
                    Section(header: Text("PROVISION NEW SHIPMENT CONTAINER")) {
                        HStack {
                            TextField("Folder Sub-Name...", text: $newBatchInputName)
                            Picker("Service", selection: $newBatchServiceSelection) {
                                Text("PSA").tag("PSA")
                                Text("BGS").tag("BGS")
                                Text("CGC").tag("CGC")
                                Text("SGC").tag("SGC")
                                Text("TAG").tag("TAG")
                            }
                            .pickerStyle(.menu)
                            Button(action: {
                                guard !newBatchInputName.isEmpty else { return }
                                portfolio.createNewSubmissionBatch(name: newBatchInputName, service: newBatchServiceSelection)
                                newBatchInputName = ""
                            }) {
                                Image(systemName: "folder.badge.plus").bold()
                            }
                        }
                    }
                    Section(header: Text("EXPORT STRATEGIES")) {
                        Button(action: {
                            isBatchExporting = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                isBatchExporting = false
                                if let generatedSheetURL = portfolio.generatePrintableSubmissionManifest() {
                                    let controller = UIActivityViewController(activityItems: [generatedSheetURL], applicationActivities: nil)
                                    if let vc = UIApplication.shared.connectedScenes
                                        .flatMap({ ($0 as? UIWindowScene)?.windows ?? [] })
                                        .first(where: { $0.isKeyWindow })?.rootViewController {
                                        controller.popoverPresentationController?.sourceView = vc.view
                                        vc.present(controller, animated: true)
                                    }
                                }
                            }
                        }) {
                            if isBatchExporting {
                                ProgressView("Generating CSV Data Stream...").frame(maxWidth: .infinity)
                            } else {
                                Label("Export Uniform CSV Logistics Sheets", systemImage: "doc.text.below.ecg.fill")
                                    .bold().frame(maxWidth: .infinity)
                            }
                        }
                        .disabled(portfolio.savedCards.isEmpty)
                    }
                    Section(header: Text("ACTIVE STAGING MATRIX (LONG-PRESS TO RE-ROUTE)")) {
                        if batchSegmentedCardRecords.isEmpty {
                            Text("No cards inside this batch filter. New live scans will assign here automatically.").font(.caption).foregroundColor(.secondary)
                        } else {
                            ForEach(batchSegmentedCardRecords) { card in
                                HStack {
                                    Image(systemName: "square.dashed").foregroundColor(.blue)
                                    VStack(alignment: .leading) {
                                        Text(card.name).font(.subheadline).bold()
                                        Text("Pre-Grade Track: PSA (card.predictedGradePSA)").font(.caption2).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text(String(format: "$%.2f", card.calculatedValue)).font(.caption).bold().foregroundColor(.green)
                                }
                                .contextMenu {
                                    Menu("Move to Destination Folder...") {
                                        ForEach(portfolio.activeSubmissionBatches) { destinationFolder in
                                            Button(action: {
                                                withAnimation {
                                                    portfolio.assignCardToBatch(cardId: card.id, batchId: destinationFolder.id)
                                                }
                                            }) {
                                                Label(destinationFolder.batchName, systemImage: "folder.badge.gearshape")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Bulk Submission")
        }
    }
    // MARK: - Sub-View 5: Professional Lab Grading Cross-Company Simulation Workspace
    private var labSimulatorView: some View {
        NavigationView {
            VStack(spacing: 0) {
                if portfolio.savedCards.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "waveform.path.ecg.rectangle").font(.largeTitle).foregroundColor(.gray)
                        Text("No Assets inside Vault Archives").font(.headline)
                        Text("Scan and commit cards inside your portfolio first to unlock secondary market delta simulations.").font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                    }
                    .padding(.top, 60)
                    Spacer()
                } else {
                    List {
                        Section(header: Text("SELECT VAULT RECORD TO EMULATE")) {
                            ForEach(portfolio.savedCards) { card in
                                Button(action: {
                                    highlightedSimulationCard = card
                                }) {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(card.name).font(.subheadline).bold()
                                            Text(card.setName).font(.caption2).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        if highlightedSimulationCard?.id == card.id {
                                            Image(systemName: "checkmark.circle.fill").foregroundColor(.blue)
                                        }
                                    }
                                }
                            }
                        }
                        if let activeSimCard = highlightedSimulationCard {
                            Section(header: Text("LAB CRITERIA SIMULATOR TARGET")) {
                                Picker("Target Lab", selection: $selectedSimulatorCompany) {
                                    Text("PSA").tag("PSA")
                                    Text("BGS").tag("BGS")
                                    Text("CGC").tag("CGC")
                                    Text("SGC").tag("SGC")
                                    Text("TAG").tag("TAG")
                                }
                                .pickerStyle(.segmented)
                                let simResults = portfolio.simulateCrossCompanyScore(for: activeSimCard, targetCompany: selectedSimulatorCompany)
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text("Simulated Outcome Score:")
                                        Spacer()
                                        Text(String(format: "%.1f Grade", simResults.grade)).font(.headline).foregroundColor(.blue)
                                    }
                                    Divider()
                                    HStack {
                                        Text("Adjusted Yield Value Projection:")
                                        Spacer()
                                        Text(String(format: "$%.2f", simResults.estimatedValue)).font(.headline).foregroundColor(.green)
                                    }
                                    Divider()
                                    if selectedSimulatorCompany == "BGS" {
                                        Text("• BGS requires 50/50 sub-millimeter border matching for a perfect 10 score. Minor skews will result in quad-grade penalties.").font(.caption2).foregroundColor(.secondary)
                                    } else if selectedSimulatorCompany == "CGC" {
                                        Text("• CGC weights surface microscopic dings tightly. Ensure your protective sleeve shields items from background light anomalies.").font(.caption2).foregroundColor(.secondary)
                                    } else if selectedSimulatorCompany == "SGC" {
                                        Text("• SGC leverages the famous black-tuxedo border holder design. Highly prioritized on crisp corner contours and edge sharpness variations.").font(.caption2).foregroundColor(.secondary)
                                    } else if selectedSimulatorCompany == "TAG" {
                                        Text("• TAG uses 100% digital robotic vision profiles, utilizing automated mathematical pixel density passes. Near-zero leniency on micro print layers.").font(.caption2).foregroundColor(.secondary)
                                    } else {
                                        Text("• PSA grants up to a 60/40 alignment leniency on front surfaces if back borders remain centered within a 75/25 threshold matrix.").font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Lab Simulator")
        }
    }
    // MARK: - Sub-View 6: Live Market Value Arbitrage Yield ROI Calculator Matrix View
    private var arbitrageMatrixView: some View {
        NavigationView {
            VStack(spacing: 0) {
                if portfolio.savedCards.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "dollarsign.circle").font(.largeTitle).foregroundColor(.gray)
                        Text("ROI Matrix Empty").font(.headline)
                        Text("Add items to your vault ledger to unlock financial arbitrage optimization tracking.").font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                    }
                    .padding(.top, 60)
                    Spacer()
                } else {
                    List {
                        Section(header: Text("CHOOSE ASSET TO OPTIMIZE")) {
                            ForEach(portfolio.savedCards) { card in
                                Button(action: {
                                    selectedArbitrageCard = card
                                }) {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(card.name).font(.subheadline).bold()
                                            Text(card.setName).font(.caption2).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        if selectedArbitrageCard?.id == card.id {
                                            Image(systemName: "dollarsign.circle.fill").foregroundColor(.green)
                                        }
                                    }
                                }
                            }
                        }
                        if let activeCard = selectedArbitrageCard {
                            Section(header: Text("LIVE ARBITRAGE OPTIMIZATION RANKINGS")) {
                                ForEach(portfolio.calculateArbitrageMatrix(for: activeCard)) { opp in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(opp.companyName)
                                                .font(.headline).foregroundColor(.primary)
                                            Spacer()
                                            Text(String(format: "+$%.2f Net ROI", opp.netProfitROI))
                                                .font(.subheadline).bold().foregroundColor(.green)
                                        }
                                        HStack {
                                            Text(String(format: "Est. Grade: %.1f", opp.projectedGrade))
                                            Spacer()
                                            Text("Turnaround: (opp.turnaroundDays) days")
                                        }
                                        .font(.caption2).foregroundColor(.secondary)
                                        ProgressView(value: min(1.0, opp.netProfitROI / activeCard.calculatedValue))
                                            .accentColor(.green)
                                            .scaleEffect(x: 1, y: 0.5, anchor: .center)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Arbitrage Matrix")
        }
    }
    // MARK: - Sub-View 7: Live Continuous 7-Day Market Valuation Tracker
    private var liveMarketTickerView: some View {
        NavigationView {
            VStack(spacing: 0) {
                if portfolio.savedCards.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.xyaxis.line").font(.largeTitle).foregroundColor(.gray)
                        Text("Market Ticker Empty").font(.headline)
                        Text("Commit scanned card assets to initialize real-time continuous market history plotting panels.").font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                    }
                    .padding(.top, 60)
                    Spacer()
                } else {
                    List {
                        Section(header: Text("CHOOSE TRACKED MARKET FEED INDEX")) {
                            ForEach(portfolio.savedCards) { card in
                                Button(action: {
                                    selectedTickerCard = card
                                }) {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(card.name).font(.subheadline).bold()
                                            Text(card.setName).font(.caption2).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        if selectedTickerCard?.id == card.id {
                                            Image(systemName: "chart.line.uptrend.xyaxis").foregroundColor(.blue)
                                        }
                                    }
                                }
                            }
                        }
                        if let activeTickerCard = selectedTickerCard {
                            Section(header: Text("7-DAY RECENT SALE PRICE TRACE INDEX")) {
                                let trendPoints = priceEngine.fetchMarketTickerHistory(for: activeTickerCard.name)
                                Chart {
                                    ForEach(trendPoints) { point in
                                        LineMark(
                                            x: .value("Day", point.dateLabel),
                                            y: .value("Price", point.closingPrice)
                                        )
                                        .foregroundStyle(Color.blue)
                                        .interpolationMethod(.monotone)
                                        PointMark(
                                            x: .value("Day", point.dateLabel),
                                            y: .value("Price", point.closingPrice)
                                        )
                                        .foregroundStyle(Color.blue)
                                    }
                                }
                                .frame(height: 180)
                                .padding(.vertical, 10)
                                HStack {
                                    Text("Current Traced Spot Price:")
                                    Spacer()
                                    Text(String(format: "$%.2f USD", activeTickerCard.calculatedValue))
                                        .font(.headline).foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Market Ticker")
        }
    }
    // MARK: - Sub-View 8: Encrypted Lab Submission QR Code Passport Form Matrix Panel
    private var labPassportManifestView: some View {
        NavigationView {
            Form {
                Section(header: Text("SELECT EXPEDITION CHANNEL")) {
                    Picker("Active Batch", selection: $passportSelectedBatchId) {
                        ForEach(portfolio.activeSubmissionBatches) { batch in
                            Text(batch.batchName).tag(Optional(batch.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section(header: Text("LAB-READY ACCELERATOR PASSPORT")) {
                    VStack(spacing: 15) {
                        Spacer()
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white)
                                .frame(width: 180, height: 180)
                                .shadow(radius: 4)
                            Image(systemName: "qrcode")
                                .font(.system(size: 140))
                                .foregroundColor(.black)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        let payload = portfolio.generateCompressedBatchPayload(for: passportSelectedBatchId)
                        Text("SECURE TRANSLATION TOKEN:")
                            .font(.caption2).bold().foregroundColor(.secondary)
                        Text(payload.prefix(28) + "...")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.blue)
                            .multilineTextAlignment(.center)
                        Text("Include this code inside your physical shipment package box. Receiving sorting laboratories scan this passport token to instantly synchronize local vault telemetry records safely.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 10)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                }
            }
            .navigationTitle("Lab Passport")
        }
    }
    // MARK: - Sub-View 9: Live Global Web Auction Deal Monitor Scan Tracking Dashboard
    private var activeMarketplaceMonitorView: some View {
        NavigationView {
            VStack(spacing: 0) {
                if portfolio.savedCards.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "cart.badge.plus").font(.largeTitle).foregroundColor(.gray)
                        Text("Auction Tracker Idle").font(.headline)
                        Text("Commit scanned card assets to initialize global auction arbitrage tracking streams.").font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                    }
                    .padding(.top, 60)
                    Spacer()
                } else {
                    List {
                        Section(header: Text("CHOOSE REPLICA TRACKING TARGET")) {
                            ForEach(portfolio.savedCards) { card in
                                Button(action: {
                                    selectedMonitorCard = card
                                }) {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(card.name).font(.subheadline).bold()
                                            Text(card.setName).font(.caption2).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        if selectedMonitorCard?.id == card.id {
                                            Image(systemName: "eye.fill").foregroundColor(.purple)
                                        }
                                    }
                                }
                            }
                        }
                        if let activeMonitorTarget = selectedMonitorCard {
                            Section(header: Text("ACTIVE LAB LISTINGS RADAR STREAM")) {
                                ForEach(priceEngine.fetchMarketTickerHistory(for: activeMonitorTarget.name)) { auction in
                                    HStack(spacing: 12) {
                                        Image(systemName: auction.closingPrice < activeMonitorTarget.calculatedValue ? "tag.circle.fill" : "circle.grid.cross.fill")
                                            .font(.title2)
                                            .foregroundColor(auction.closingPrice < activeMonitorTarget.calculatedValue ? .green : .gray)
                                        VStack(alignment: .leading) {
                                            Text("Market Match Deal Instance").font(.subheadline).bold()
                                            Text(auction.dateLabel).font(.caption2).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing) {
                                            Text(String(format: "$%.2f", auction.closingPrice))
                                                .font(.subheadline).bold()
                                                .foregroundColor(auction.closingPrice < activeMonitorTarget.calculatedValue ? .green : .primary)
                                            if auction.closingPrice < activeMonitorTarget.calculatedValue {
                                                Text("BELOW VALUE").font(.system(size: 7, weight: .black))
                                                    .padding(3).background(Color.green.opacity(0.15))
                                                    .cornerRadius(4).foregroundColor(.green)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Live Deals Radar")
        }
    }
    // MARK: - Isolated Parameter Computation Helpers
    private func computeStrictGrade(result: CenteringResult, score: Double) -> Double {
        if selectedCategory == .sports && !result.passesBGS10 { return max(1.0, score - 0.5) }
        return score
    }
    private func computeDynamicPrice(strictGrade: Double, psa10Value: Double) -> Double {
        let dynamicValueMultiplier = max(0.1, (strictGrade / 10.0))
        let targetBasePrice = selectedCategory == .sports ? 185.00 : psa10Value
        return targetBasePrice * dynamicValueMultiplier
    }
    // MARK: - View Component Sub-layers
    @ViewBuilder
    private func ExportManifestButton() -> some View {
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
            Label("PDF", systemImage: "doc.badge.gearshape.fill").font(.system(size: 9, weight: .bold)).foregroundColor(.blue)
        }
    }
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
    @ViewBuilder
    private func CenteringGuideOverlay(ratios: CenteringResult) -> some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 105))
                path.addLine(to: CGPoint(x: 170, y: 105))
            }
            .stroke(Color.blue.opacity(0.4), lineWidth: 1)
            Path { path in
                path.move(to: CGPoint(x: 85, y: 0))
                path.addLine(to: CGPoint(x: 85, y: 210))
            }
            .stroke(Color.blue.opacity(0.4), lineWidth: 1)
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
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.green)
            .padding(6)
        }
        .frame(width: 170, height: 210)
    }
    @ViewBuilder
    private func ZionHStackRow(result: CenteringResult, grade: CalculatedGrade, value: CardValuation) -> some View {
        let finalStrictGrade = computeStrictGrade(result: result, score: grade.finalScore)
        let finalProjectedPrice = computeDynamicPrice(strictGrade: finalStrictGrade, psa10Value: value.marketValuePSA10)
        let cardNameString = selectedCategory == .sports ? "Paige Bueckers Rookie Prizm" : value.cardName
        let setNameString = selectedCategory == .sports ? "Panini WNBA (2026)" : value.setName
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Calculated Condition:")
                Spacer()
                Text(String(format: "PRE-GRADE %.1f", finalStrictGrade))
                    .font(.title2).bold()
                    .foregroundColor(finalStrictGrade >= 9.5 ? .green : .blue)
            }
            Text(grade.primaryFlawDescription).font(.caption).foregroundColor(.secondary).italic()
            Divider()
            HStack {
                Text("Dynamic Value Projection:")
                Spacer()
                Text(String(format: "$%.2f", finalProjectedPrice)).bold().foregroundColor(.green)
            }
            Divider()
            Button(action: {
                portfolio.appendCard(
                    name: cardNameString,
                    set: setNameString,
                    lrCentering: String(format: "%.1f%% / %.1f%%", result.leftRightRatio.left, result.leftRightRatio.right),
                    tbCentering: String(format: "%.1f%% / %.1f%%", result.topBottomRatio.top, result.topBottomRatio.bottom),
                    predictedGrade: Int(finalStrictGrade),
                    marketValue: finalProjectedPrice
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
        let activeQueryLookupKey = selectedCategory == .sports ? "paige-bueckers-prizm" : automaticCardIdentifier
        priceEngine.fetchLiveValuations(cardId: activeQueryLookupKey, category: selectedCategory) { result in
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
        self.automaticCardIdentifier = "Scanning..."
    }
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
            let scratchCount = automatedDefects.surfaceScratchCount
            let whiteningSeverity = automatedDefects.edgeWhiteningSeverity
            let evaluatedGrade = self.gradingJudge.evaluateCardCondition(
                centering: computedCentering,
                surfaceScratchesDetected: scratchCount,
                edgeWhiteningCount: whiteningSeverity
            )
            self.centeringAnalyzer.extractCardIdentifierText(from: imageFrame, cardBoundingBox: cardRect) { foundTextString in
                DispatchQueue.main.async {
                    if let serialCode = foundTextString {
                        self.automaticCardIdentifier = serialCode
                    }
                }
            }
            DispatchQueue.main.async {
                self.scanResult = computedCentering
                self.manualSurfaceScratches = Double(scratchCount)
                self.manualEdgeWhitening = Double(whiteningSeverity)
                self.calculatedGrade = evaluatedGrade
            }
        }
    }
}

