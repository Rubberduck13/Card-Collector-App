import Foundation
import SwiftData
import Combine

// MARK: - Model

@Model
public final class CollectorCard {

    @Attribute(.unique)
    public var id: UUID

    public var name: String
    public var setName: String

    @Attribute(.externalStorage)
    public var imageData: Data?

    // Centering
    public var leftToRightRatio: Double
    public var topToBottomRatio: Double

    // Estimated Grade
    public var estimatedGrade: Double

    // Metadata
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        setName: String,
        imageData: Data? = nil,
        leftToRightRatio: Double = 0.5,
        topToBottomRatio: Double = 0.5,
        estimatedGrade: Double = 0.0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.setName = setName
        self.imageData = imageData
        self.leftToRightRatio = leftToRightRatio
        self.topToBottomRatio = topToBottomRatio
        self.estimatedGrade = estimatedGrade
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func updateCentering(
        leftToRightRatio: Double,
        topToBottomRatio: Double
    ) {
        self.leftToRightRatio = leftToRightRatio
        self.topToBottomRatio = topToBottomRatio
        self.updatedAt = .now
    }

    public func updateEstimatedGrade(_ grade: Double) {
        self.estimatedGrade = grade
        self.updatedAt = .now
    }
}

// MARK: - State Manager

@MainActor
public final class PortfolioState: ObservableObject {

    @Published public private(set) var cards: [CollectorCard] = []

    public let modelContainer: ModelContainer
    public let modelContext: ModelContext

    public init(inMemory: Bool = false) throws {

        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: inMemory
        )

        modelContainer = try ModelContainer(
            for: CollectorCard.self,
            configurations: configuration
        )

        modelContext = ModelContext(modelContainer)

        try fetchCards()
    }

    // MARK: - Fetch

    public func fetchCards() throws {

        let descriptor = FetchDescriptor<CollectorCard>(
            sortBy: [
                SortDescriptor(\.createdAt, order: .reverse)
            ]
        )

        cards = try modelContext.fetch(descriptor)
    }

    // MARK: - Add

    @discardableResult
    public func addCard(
        name: String,
        setName: String,
        imageData: Data?,
        leftToRightRatio: Double,
        topToBottomRatio: Double,
        estimatedGrade: Double
    ) throws -> CollectorCard {

        let card = CollectorCard(
            name: name,
            setName: setName,
            imageData: imageData,
            leftToRightRatio: leftToRightRatio,
            topToBottomRatio: topToBottomRatio,
            estimatedGrade: estimatedGrade
        )

        modelContext.insert(card)

        try save()

        return card
    }

    // MARK: - Delete

    public func delete(_ card: CollectorCard) throws {

        modelContext.delete(card)

        try save()
    }

    public func delete(at offsets: IndexSet) throws {

        for index in offsets {
            modelContext.delete(cards[index])
        }

        try save()
    }

    // MARK: - Update

    public func update(_ card: CollectorCard) throws {

        card.updatedAt = .now

        try save()
    }

    // MARK: - Save

    public func save() throws {

        if modelContext.hasChanges {
            try modelContext.save()
        }

        try fetchCards()
    }

    // MARK: - Helpers

    public func card(with id: UUID) -> CollectorCard? {
        cards.first(where: { $0.id == id })
    }

    public var totalCards: Int {
        cards.count
    }

    public func removeAll() throws {

        for card in cards {
            modelContext.delete(card)
        }

        try save()
    }
}
