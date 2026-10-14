import XCTest
@testable import BariatricHabits

final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.cannotConnectToHost) }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

final class BridgeClientTests: XCTestCase {
    private var client: BridgeClient!

    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        client = BridgeClient(baseURL: URL(string: "http://100.64.0.1:8787")!, token: "secret",
                              session: URLSession(configuration: config))
    }

    override func tearDown() { StubURLProtocol.handler = nil }

    func test_analyze_sends_token_and_decodes_snake_case() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/analyze")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/jpeg")
            return (200, Data(#"{"items":[{"name":"ביצה","grams":50,"protein_g":6.3,"confidence":"high"}],"notes":""}"#.utf8))
        }
        let result = try await client.analyze(jpeg: Data([0xFF, 0xD8]))
        XCTAssertEqual(result.items, [AnalyzedItem(name: "ביצה", grams: 50, proteinG: 6.3, confidence: .high)])
    }

    func test_status_codes_map_to_errors() async {
        let cases: [(Int, BridgeError)] = [(401, .unauthorized), (502, .badModelOutput), (503, .claudeUnavailable),
                                           (504, .timeout), (500, .server(500))]
        for (status, expected) in cases {
            StubURLProtocol.handler = { _ in (status, Data("{}".utf8)) }
            do {
                _ = try await client.health()
                XCTFail("expected \(expected)")
            } catch {
                XCTAssertEqual(error as? BridgeError, expected)
            }
        }
    }

    func test_network_failure_is_unreachable() async {
        StubURLProtocol.handler = { _ in throw URLError(.timedOut) }
        do { _ = try await client.health(); XCTFail("expected error") } catch {
            XCTAssertEqual(error as? BridgeError, .unreachable)
        }
    }

    func test_undecodable_success_body_is_badModelOutput() async {
        StubURLProtocol.handler = { _ in (200, Data("nope".utf8)) }
        do { _ = try await client.analyze(jpeg: Data()); XCTFail("expected error") } catch {
            XCTAssertEqual(error as? BridgeError, .badModelOutput)
        }
    }

    func test_recipe_encodes_snake_case_body() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/recipe")
            return (200, Data(#"{"name":"מוס","ingredients":["טונה"],"steps":["לערבב"],"protein_per_portion":20,"portion_text":"מנה"}"#.utf8))
        }
        let suggestion = try await client.recipe(RecipeRequest(remainingG: 30, stage: .soft, have: []))
        XCTAssertEqual(suggestion.proteinPerPortion, 20)
    }
}

final class BridgeConfigTests: XCTestCase {
    func test_normalizes_loose_addresses() {
        XCTAssertEqual(BridgeConfig.normalizedURL(from: "100.64.1.2")?.absoluteString, "http://100.64.1.2:8787")
        XCTAssertEqual(BridgeConfig.normalizedURL(from: " 100.64.1.2:9000 ")?.absoluteString, "http://100.64.1.2:9000")
        XCTAssertEqual(BridgeConfig.normalizedURL(from: "http://mac.tail1234.ts.net:8787/")?.absoluteString,
                       "http://mac.tail1234.ts.net:8787")
    }

    func test_rejects_invalid_addresses() {
        XCTAssertNil(BridgeConfig.normalizedURL(from: ""))
        XCTAssertNil(BridgeConfig.normalizedURL(from: "ftp://mac.local"))
        XCTAssertNil(BridgeConfig.normalizedURL(from: "http://"))
    }

    func test_keychain_round_trip() throws {
        let account = "test-\(UUID().uuidString)"
        try KeychainStore.save("abc", account: account)
        XCTAssertEqual(KeychainStore.load(account: account), "abc")
        try KeychainStore.save("def", account: account)
        XCTAssertEqual(KeychainStore.load(account: account), "def")
        KeychainStore.delete(account: account)
        XCTAssertNil(KeychainStore.load(account: account))
    }
}
