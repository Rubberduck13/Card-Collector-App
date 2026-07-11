import Foundation

// MARK: - Market Price Models

public struct MarketPriceResponse: Decodable {
    public let low: Double
    public let average: Double
    public let high: Double
}

public enum PricingEngineError: Error {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case decodingFailed
}

public final class PricingEngine {

    /// Replace with your own endpoint.
    private let baseURL: URL

    /// API key supplied by your backend or secure configuration.
    private let apiKey: String

    private let session: URLSession

    public init(
        baseURL: URL,
        apiKey: String,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    /// Fetches the latest market pricing for a card.
    ///
    /// - Parameters:
    ///   - cardName: Name of the card.
    ///   - setName: Set or expansion name.
    ///   - predictedGrade: Estimated grade (e.g. 9.5 or 10).
    ///
    /// - Returns: Decoded market pricing.
    public func fetchPrice(
        cardName: String,
        setName: String,
        predictedGrade: Double
    ) async throws -> MarketPriceResponse {

        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/pricing"),
            resolvingAgainstBaseURL: false
        ) else {
            throw PricingEngineError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "card", value: cardName),
            URLQueryItem(name: "set", value: setName),
            URLQueryItem(name: "grade", value: String(predictedGrade))
        ]

        guard let url = components.url else {
            throw PricingEngineError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PricingEngineError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw PricingEngineError.httpError(httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(
                MarketPriceResponse.self,
                from: data
            )
        } catch {
            throw PricingEngineError.decodingFailed
        }
    }
}
