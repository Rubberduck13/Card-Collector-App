import Foundation
import Combine
import UIKit
import PDFKit

public struct SavedCard: Identifiable, Codable {
    public let id: UUID
    public let name: String
    public let setName: String
    public let scannedDate: Date
    public let leftRightCentering: String
    public let topBottomCentering: String
    public let predictedGradePSA: Int
    public let calculatedValue: Double
    
    public init(id: UUID = UUID(), name: String, setName: String, scannedDate: Date = Date(), leftRightCentering: String, topBottomCentering: String, predictedGradePSA: Int, calculatedValue: Double) {
        self.id = id
        self.name = name
        self.setName = setName
        self.scannedDate = scannedDate
        self.leftRightCentering = leftRightCentering
        self.topBottomCentering = topBottomCentering
        self.predictedGradePSA = predictedGradePSA
        self.calculatedValue = calculatedValue
    }
}

// Data model for our portfolio historical data plots
public struct PortfolioSnapshot: Identifiable {
    public let id = UUID()
    public let date: Date
    public let value: Double
}

public class PortfolioState: ObservableObject {
    
    @Published public var savedCards: [SavedCard] = [] {
        didSet {
            saveToDisk()
        }
    }
    
    // NEW: Dynamic timeline points used to draw our graph
    public var historicalTrendSnapshots: [PortfolioSnapshot] {
        let calendar = Calendar.current
        let today = Date()
        
        // Simulating 5 data track days to give the chart a realistic curve
        let baseValue = totalPortfolioValue
        return [
            PortfolioSnapshot(date: calendar.date(byAdding: .day, value: -4, to: today)!, value: baseValue * 0.75),
            PortfolioSnapshot(date: calendar.date(byAdding: .day, value: -3, to: today)!, value: baseValue * 0.82),
            PortfolioSnapshot(date: calendar.date(byAdding: .day, value: -2, to: today)!, value: baseValue * 0.80),
            PortfolioSnapshot(date: calendar.date(byAdding: .day, value: -1, to: today)!, value: baseValue * 0.95),
            PortfolioSnapshot(date: today, value: baseValue)
        ]
    }
    
    private let storageKey = "com.cardgrader.portfoliostate.data"
    
    public init() {
        loadFromDisk()
    }
    
    public var totalPortfolioValue: Double {
        savedCards.reduce(0) { $0 + $1.calculatedValue }
    }
    
    public func appendCard(name: String, set: String, lrCentering: String, tbCentering: String, predictedGrade: Int, marketValue: Double) {
        let newCard = SavedCard(
            name: name,
            setName: set,
            leftRightCentering: lrCentering,
            topBottomCentering: tbCentering,
            predictedGradePSA: predictedGrade,
            calculatedValue: marketValue
        )
        self.savedCards.append(newCard)
    }
    
    public func deleteCard(at offsets: IndexSet) {
        self.savedCards.remove(atOffsets: offsets)
    }
    
    private func saveToDisk() {
        if let encodedData = try? JSONEncoder().encode(savedCards) {
            UserDefaults.standard.set(encodedData, forKey: storageKey)
        }
    }
    
    private func loadFromDisk() {
        guard let rawData = UserDefaults.standard.data(forKey: storageKey),
              let decodedCards = try? JSONDecoder().decode([SavedCard].self, from: rawData) else {
            return
        }
        self.savedCards = decodedCards
    }
    /// Generates a standardized, professional grading manifest document for physical mail-in submittal tasks
    public func generatePrintableSubmissionManifest() -> URL? {
        let pdfMetaData = [
            "Subject": "Official Grading Submission Manifest & Technical Report Card",
            "Author": "AI Grade Professional Card Scanner System"
        ]
        
        let formatLayoutFormat = UIGraphicsPDFRendererFormat()
        formatLayoutFormat.documentInfo = pdfMetaData as [String : Any]
        
        // Establish standard physical A4 paper page printing dimension coordinates (8.5 x 11 inches)
        let pageBoundsWidth: CGFloat = 612
        let pageBoundsHeight: CGFloat = 792
        let targetedRenderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageBoundsWidth, height: pageBoundsHeight), format: formatLayoutFormat)
        
        // Define local sandbox file storage pathways to host our cached document file
        let compilationFilename = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AI_Grade_Submission_Manifest.pdf")
        
        do {
            try targetedRenderer.writePDF(to: compilationFilename) { layoutContext in
                layoutContext.beginPage()
                
                // 1. Draw Title Header Block
                let mainTitleHeader = "AI GRADE SCANNER: SUBMISSION MANIFEST"
                let structuralTitleAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 22),
                    .foregroundColor: UIColor.systemBlue
                ]
                mainTitleHeader.draw(at: CGPoint(x: 36, y: 40), withAttributes: structuralTitleAttributes)
                
                // 2. Draw Metadata Summary Sub-blocks
                let generatedSubtitleTimestamp = "Manifest Date: \(Date().description) | Verified Records: \(savedCards.count)"
                let metadataTextAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 10),
                    .foregroundColor: UIColor.secondaryLabel
                ]
                generatedSubtitleTimestamp.draw(at: CGPoint(x: 36, y: 70), withAttributes: metadataTextAttributes)
                
                // Draw a structural dividing line baseline
                let anchorPath = UIBezierPath()
                anchorPath.move(to: CGPoint(x: 36, y: 90))
                anchorPath.addLine(to: CGPoint(x: 576, y: 90))
                anchorPath.lineWidth = 1
                UIColor.separator.setStroke()
                anchorPath.stroke()
                
                // 3. Populate Scanned Items Matrix List
                var runningVerticalYAnchor: CGFloat = 110
                let tableHeaderColumnTitles = "Asset Name & Set Context Info                          Predicted Grade       Est. Market Value"
                let subheaderAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 11), .foregroundColor: UIColor.label]
                tableHeaderColumnTitles.draw(at: CGPoint(x: 36, y: runningVerticalYAnchor), withAttributes: subheaderAttributes)
                runningVerticalYAnchor += 20
                
                for singleCardData in savedCards {
                    // Check paper boundary floor limits to prevent overflow layout breaks
                    if runningVerticalYAnchor > 720 {
                        layoutContext.beginPage()
                        runningVerticalYAnchor = 50
                    }
                    
                    // Render Item Title Row Context Strings
                    let descriptiveRowString = "\(singleCardData.name) (\(singleCardData.setName))"
                    let rowDataValueAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.label]
                    descriptiveRowString.draw(at: CGPoint(x: 36, y: runningVerticalYAnchor), withAttributes: rowDataValueAttributes)
                    
                    let gradeString = "PSA \(singleCardData.predictedGradePSA)"
                    gradeString.draw(at: CGPoint(x: 390, y: runningVerticalYAnchor), withAttributes: rowDataValueAttributes)
                    
                    let currencyTextString = String(format: "$%.2f", singleCardData.calculatedValue)
                    let absoluteCurrencyValueAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 10), .foregroundColor: UIColor.systemGreen]
                    currencyTextString.draw(at: CGPoint(x: 500, y: runningVerticalYAnchor), withAttributes: absoluteCurrencyValueAttributes)
                    
                    runningVerticalYAnchor += 25
                }
                
                // 4. Render Cumulative Appraisal Financial Block
                runningVerticalYAnchor += 15
                let totalNetValueSummaryString = String(format: "Total Estimated Vault Shipment Value Evaluation: $%.2f", totalPortfolioValue)
                let grandSummaryTextAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 12),
                    .foregroundColor: UIColor.systemBlue
                ]
                totalNetValueSummaryString.draw(at: CGPoint(x: 36, y: runningVerticalYAnchor), withAttributes: grandSummaryTextAttributes)
            }
            return compilationFilename
        } catch {
            print("Failed to complete system PDF layout compilation operations.")
            return nil
        }
    }
}

