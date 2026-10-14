import Foundation

struct AnalyzedItem: Codable, Equatable {
    var name: String
    var grams: Double
    var proteinG: Double
    var confidence: FoodConfidence
}

struct AnalysisResult: Codable, Equatable {
    var items: [AnalyzedItem]
    var notes: String
}

struct RecipeRequest: Codable, Equatable {
    var remainingG: Double
    var stage: DietStage
    var have: [String]
}

struct RecipeSuggestion: Codable, Equatable {
    var name: String
    var ingredients: [String]
    var steps: [String]
    var proteinPerPortion: Double
    var portionText: String
}

struct BridgeHealth: Codable, Equatable {
    var status: String
    var claude: Bool
}

enum BridgeError: Error, Equatable {
    case unreachable, unauthorized, badModelOutput, claudeUnavailable, timeout
    case server(Int)

    var messageHe: String {
        switch self {
        case .unreachable: "המק לא זמין כרגע. הארוחה תזוהה כשיהיה חיבור."
        case .unauthorized: "הטוקן שגוי. בדקו אותו בהגדרות."
        case .badModelOutput: "לא הצלחתי להבין את התשובה. אפשר להזין ידנית."
        case .claudeUnavailable: "Claude לא מחובר על המק. פתחו טרמינל במק והריצו claude כדי להתחבר."
        case .timeout: "הזיהוי לקח יותר מדי זמן. ננסה שוב."
        case .server(let code): "שגיאה במק (\(code))."
        }
    }
}

protocol BridgeClienting {
    func analyze(jpeg: Data) async throws -> AnalysisResult
    func recipe(_ request: RecipeRequest) async throws -> RecipeSuggestion
    func health() async throws -> BridgeHealth
}

struct BridgeClient: BridgeClienting {
    private static let requestTimeout: TimeInterval = 90

    let baseURL: URL
    let token: String
    let session: URLSession

    init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    func analyze(jpeg: Data) async throws -> AnalysisResult {
        var request = makeRequest(path: "analyze", method: "POST")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = jpeg
        return try await send(request)
    }

    func recipe(_ recipeRequest: RecipeRequest) async throws -> RecipeSuggestion {
        var request = makeRequest(path: "recipe", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(recipeRequest)
        return try await send(request)
    }

    func health() async throws -> BridgeHealth {
        try await send(makeRequest(path: "health", method: "GET"))
    }

    private func makeRequest(path: String, method: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: Self.requestTimeout)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw BridgeError.unreachable
        }
        guard let http = response as? HTTPURLResponse else { throw BridgeError.unreachable }
        switch http.statusCode {
        case 200:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            guard let value = try? decoder.decode(T.self, from: data) else { throw BridgeError.badModelOutput }
            return value
        case 401: throw BridgeError.unauthorized
        case 502: throw BridgeError.badModelOutput
        case 503: throw BridgeError.claudeUnavailable
        case 504: throw BridgeError.timeout
        default: throw BridgeError.server(http.statusCode)
        }
    }
}

enum BridgeConfig {
    static let tokenAccount = "bridgeToken"
    static let defaultPort = 8787

    /// Accepts "100.64.1.2", "host:9000", "http://host.ts.net:8787/" → "http://host:port".
    static func normalizedURL(from raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        guard var components = URLComponents(string: text),
              components.scheme == "http" || components.scheme == "https",
              let host = components.host, !host.isEmpty else { return nil }
        if components.port == nil { components.port = defaultPort }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }

    @MainActor
    static func makeClient(settings: AppSettings) -> BridgeClienting? {
        guard let raw = settings.bridgeURL, let url = normalizedURL(from: raw),
              let token = KeychainStore.load(account: tokenAccount), !token.isEmpty else { return nil }
        return BridgeClient(baseURL: url, token: token)
    }
}
