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
    func analyze(jpeg: Data, cookingNote: String?) async throws -> AnalysisResult
    func recipe(_ request: RecipeRequest) async throws -> RecipeSuggestion
    func health() async throws -> BridgeHealth
}

struct BridgeClient: BridgeClienting {
    /// Above the bridge's worst case (CLAUDE_TIMEOUT_SECONDS = 120 plus lock wait),
    /// so the phone never gives up on an analysis the Mac is still finishing.
    static let analyzeTimeout: TimeInterval = 150
    static let recipeTimeout: TimeInterval = 150
    static let healthTimeout: TimeInterval = 10

    let baseURL: URL
    let token: String
    let session: URLSession

    init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    /// RFC 3986 unreserved characters only. `.alphanumerics` would let Hebrew letters through,
    /// and HTTP header values must be ASCII.
    private static let headerSafeCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    func analyze(jpeg: Data, cookingNote: String?) async throws -> AnalysisResult {
        var request = makeRequest(path: "analyze", method: "POST", timeout: Self.analyzeTimeout)
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        if let cookingNote, let encoded = cookingNote.addingPercentEncoding(withAllowedCharacters: Self.headerSafeCharacters) {
            request.setValue(encoded, forHTTPHeaderField: "X-Cooking-Note")
        }
        request.httpBody = jpeg
        return try await send(request)
    }

    func recipe(_ recipeRequest: RecipeRequest) async throws -> RecipeSuggestion {
        var request = makeRequest(path: "recipe", method: "POST", timeout: Self.recipeTimeout)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(recipeRequest)
        return try await send(request)
    }

    func health() async throws -> BridgeHealth {
        try await send(makeRequest(path: "health", method: "GET", timeout: Self.healthTimeout))
    }

    private func makeRequest(path: String, method: String, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            // A cancelled task must stay distinguishable from an unreachable Mac.
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
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
    /// Only Tailscale addresses (100.64.0.0/10 or *.ts.net) and localhost are allowed, so a
    /// mistyped address never sends the bearer token over cleartext to a stranger.
    static func normalizedURL(from raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        guard var components = URLComponents(string: text),
              components.scheme == "http" || components.scheme == "https",
              let host = components.host, isAllowedHost(host) else { return nil }
        if components.port == nil { components.port = defaultPort }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }

    static func isAllowedHost(_ host: String) -> Bool {
        let host = host.lowercased()
        if host == "localhost" || host == "127.0.0.1" { return true }
        if host.hasSuffix(".ts.net") && host.count > ".ts.net".count { return true }
        return isTailscaleIPv4(host)
    }

    /// Tailscale's CGNAT range 100.64.0.0/10: first octet 100, second octet 64–127.
    private static func isTailscaleIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let octets = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.count <= 3, part.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(part),
                  (0...255).contains(value) else { return nil }
            return value
        }
        guard octets.count == 4 else { return false }
        return octets[0] == 100 && (64...127).contains(octets[1])
    }

    @MainActor
    static func makeClient(settings: AppSettings) -> BridgeClienting? {
        guard let raw = settings.bridgeURL, let url = normalizedURL(from: raw),
              let token = KeychainStore.load(account: tokenAccount), !token.isEmpty else { return nil }
        return BridgeClient(baseURL: url, token: token)
    }
}
