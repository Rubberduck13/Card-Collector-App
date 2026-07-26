import Foundation
import SwiftUI

// Struct tracking individual card entries committed from the scanner
public struct SavedCard: Identifiable, Codable {
    public let id: UUID
    public let name: String
    public let setName: String
    public let lrCenteringResult: String
    public let tbCenteringResult: String
    public let predictedGradePSA: Int
    public let calculatedValue: Double
    public var targetBatchId: UUID? // Links a card directly to a specific batch assignment folder
    
    public init(id: UUID = UUID(), name: String, set: String, lrCentering: String, tbCentering: String, predictedGrade: Int, marketValue: Double, batchId: UUID? = nil) {
        self.id = id
        self.name = name
        self.setName = set
        self.lrCenteringResult = lrCentering
        self.tbCenteringResult = tbCentering
        self.predictedGradePSA = predictedGrade
        self.calculatedValue = marketValue
        self.targetBatchId = batchId
    }
}

// Struct tracking historical value timestamps for Apple Charts trend metrics
public struct ValueSnapshot: Identifiable, Codable {
    public let id: UUID
    public let date: Date
    public let value: Double
    
    public init(id: UUID = UUID(), date: Date, value: Double) {
        self.id = id
        self.date = date
        self.value = value
    }
}

// NEW: Model wrapping a dedicated bulk submission container folder
public struct SubmissionBatch: Identifiable, Codable {
    public let id: UUID
    public var batchName: String
    public var gradingServiceTarget: String // e.g., "PSA", "BGS", "SGC"
    public var creationDate: Date
    
    public init(id: UUID = UUID(), name: String, service: String = "PSA", date: Date = Date()) {
        self.id = id
        self.batchName = name
        self.gradingServiceTarget = service
        self.creationDate = date
    }
}

public class PortfolioState: ObservableObject {
    
    @Published public var savedCards: [SavedCard] = []
    @Published public var historicalTrendSnapshots: [ValueSnapshot] = []
    @Published public var activeSubmissionBatches: [SubmissionBatch] = [] // Tracks user grouping folders
    
    private let storageKeyCards = "com.cardgrader.portfolio.savedcards"
    private let storageKeyTrend = "com.cardgrader.portfolio.trendsnapshots"
    private let storageKeyBatches = "com.cardgrader.portfolio.activebatches"
    
    public var totalPortfolioValue: Double {
        savedCards.reduce(0.0) { $0 + $1.calculatedValue }
    }
    
    public init() {
        loadDataFromPersistentDisk()
        
        // Seed default foundational data records if disk workspace returns empty
        if activeSubmissionBatches.isEmpty {
            createNewSubmissionBatch(name: "PSA Quarter Bulk Tier", service: "PSA")
            createNewSubmissionBatch(name: "BGS Express Autographs", service: "BGS")
        }
        if historicalTrendSnapshots.isEmpty && totalPortfolioValue > 0 {
            seedInitialTrendCurveMetrics()
        }
    }
    
    // MARK: - Core Portfolio Data Modification Networks
    public func appendCard(name: String, set: String, lrCentering: String, tbCentering: String, predictedGrade: Int, marketValue: Double) {
        // Automatically assign card to the newest active batch folder if one exists
        let fallbackBatchId = activeSubmissionBatches.first?.id
        
        let targetNewCard = SavedCard(
            name: name,
            set: set,
            lrCentering: lrCentering,
            tbCentering: tbCentering,
            predictedGrade: predictedGrade,
            marketValue: marketValue,
            batchId: fallbackBatchId
        )
        
        savedCards.append(targetNewCard)
        appendLiveTrendSnapshotRecord(with: totalPortfolioValue)
        saveDataToPersistentDisk()
    }
    
    public func deleteCard(at offsets: IndexSet) {
        savedCards.remove(atOffsets: offsets)
        appendLiveTrendSnapshotRecord(with: totalPortfolioValue)
        saveDataToPersistentDisk()
    }
    
    // MARK: - NEW: Bulk Shipping Batch Folder Allocation Networks
    public func createNewSubmissionBatch(name: String, service: String) {
        let newBatch = SubmissionBatch(name: name, service: service)
        activeSubmissionBatches.append(newBatch)
        saveDataToPersistentDisk()
    }
    
    public func assignCardToBatch(cardId: UUID, batchId: UUID) {
        if let cardIndex = savedCards.firstIndex(where: { $0.id == cardId }) {
            let oldCard = savedCards[cardIndex]
            savedCards[cardIndex] = SavedCard(
                id: oldCard.id,
                name: oldCard.name,
                set: oldCard.setName,
                lrCentering: oldCard.lrCenteringResult,
                tbCentering: oldCard.tbCenteringResult,
                predictedGrade: oldCard.predictedGradePSA,
                marketValue: oldCard.calculatedValue,
                batchId: batchId
            )
            saveDataToPersistentDisk()
        }
    }
    
    public func removeBatch(at offsets: IndexSet) {
        activeSubmissionBatches.remove(atOffsets: offsets)
        saveDataToPersistentDisk()
    }
    
    // MARK: - Document Export Spreadsheet Manifest Generators
    public func generatePrintableSubmissionManifest() -> URL? {
        let manifestDocumentFileName = "Bulk_Grading_Manifest_Invoice.csv"
        guard let deviceCacheDirectoryPath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        
        let outputTargetURL = deviceCacheDirectoryPath.appendingPathComponent(manifestDocumentFileName)
        
        var csvStringDocumentPayload = "Card Name,Expansion Set,L/R Centering,T/B Centering,Predicted PSA Grade,Market Valuation Projections,Assigned Batch Folder\n"
        
        for asset in savedCards {
            let assignedFolderName = activeSubmissionBatches.first(where: { $0.id == asset.targetBatchId })?.batchName ?? "Unassigned Vault"
            let layoutRowString = "\"\(asset.name)\",\"\(asset.setName)\",\"\(asset.lrCenteringResult)\",\"\(asset.tbCenteringResult)\",\(asset.predictedGradePSA),\(asset.calculatedValue),\"\(assignedFolderName)\"\n"
            csvStringDocumentPayload.append(layoutRowString)
        }
        
        do {
            try csvStringDocumentPayload.write(to: outputTargetURL, atomically: true, encoding: .utf8)
            return outputTargetURL
        } catch {
            return nil
        }
    }
    
    // MARK: - Disk Persistence Engines
    private func saveDataToPersistentDisk() {
        let jsonEncoder = JSONEncoder()
        if let cardsData = try? jsonEncoder.encode(savedCards) {
            UserDefaults.standard.set(cardsData, forKey: storageKeyCards)
        }
        if let trendData = try? jsonEncoder.encode(historicalTrendSnapshots) {
            UserDefaults.standard.set(trendData, forKey: storageKeyTrend)
        }
        if let batchesData = try? jsonEncoder.encode(activeSubmissionBatches) {
            UserDefaults.standard.set(batchesData, forKey: storageKeyBatches)
        }
    }
    
    private func loadDataFromPersistentDisk() {
        let jsonDecoder = JSONDecoder()
        if let cardsData = UserDefaults.standard.data(forKey: storageKeyCards),
           let parsedCards = try? jsonDecoder.decode([SavedCard].self, from: cardsData) {
            self.savedCards = parsedCards
        }
        if let trendData = UserDefaults.standard.data(forKey: storageKeyTrend),
           let parsedSnapshots = try? jsonDecoder.decode([ValueSnapshot].self, from: trendData) {
            self.historicalTrendSnapshots = parsedSnapshots
        }
        if let batchesData = UserDefaults.standard.data(forKey: storageKeyBatches),
           let parsedBatches = try? jsonDecoder.decode([SubmissionBatch].self, from: batchesData) {
            self.activeSubmissionBatches = parsedBatches
        }
    }
    
    private func appendLiveTrendSnapshotRecord(with currentTotalValue: Double) {
        let newSnapshot = ValueSnapshot(date: Date(), value: currentTotalValue)
        historicalTrendSnapshots.append(newSnapshot)
        if historicalTrendSnapshots.count > 30 { historicalTrendSnapshots.removeFirst() }
    }
    
    private func seedInitialTrendCurveMetrics() {
        let currentTimeline = Date()
        self.historicalTrendSnapshots = [
            ValueSnapshot(date: currentTimeline.addingTimeInterval(-86400 * 4), value: totalPortfolioValue * 0.88),
            ValueSnapshot(date: currentTimeline.addingTimeInterval(-86400 * 3), value: totalPortfolioValue * 0.92),
            ValueSnapshot(date: currentTimeline.addingTimeInterval(-86400 * 2), value: totalPortfolioValue * 0.90),
            ValueSnapshot(date: currentTimeline.addingTimeInterval(-86400 * 1), value: totalPortfolioValue * 0.96),
            ValueSnapshot(date: currentTimeline, value: totalPortfolioValue)
        ]
        saveDataToPersistentDisk()
    }
}
