import UIKit
import XCTest
@testable import BariatricHabits

final class FakeBridgeClient: BridgeClienting {
    var analyzeResults: [Result<AnalysisResult, BridgeError>] = []
    private(set) var analyzeCalls = 0

    func analyze(jpeg: Data) async throws -> AnalysisResult {
        analyzeCalls += 1
        try await Task.sleep(nanoseconds: 10_000_000)
        guard !analyzeResults.isEmpty else { throw BridgeError.unreachable }
        return try analyzeResults.removeFirst().get()
    }

    func recipe(_ request: RecipeRequest) async throws -> RecipeSuggestion { throw BridgeError.unreachable }
    func health() async throws -> BridgeHealth { BridgeHealth(status: "ok", claude: true) }
}

@MainActor
final class AnalysisQueueTests: XCTestCase {
    private var store: AppStore!
    private var photos: PhotoStore!
    private var client: FakeBridgeClient!
    private var queue: AnalysisQueue!

    private let egg = AnalysisResult(items: [AnalyzedItem(name: "ביצה", grams: 50, proteinG: 6.3, confidence: .high)],
                                     notes: "נראה טעים")

    override func setUp() {
        store = makeTestStore()
        photos = PhotoStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        client = FakeBridgeClient()
        let client = client!
        queue = AnalysisQueue(store: store, photos: photos, makeClient: { client })
    }

    @discardableResult
    private func addPending(withPhoto: Bool = true) throws -> FoodEntry {
        let name = withPhoto
            ? try photos.save(UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in })
            : "missing.jpg"
        let entry = FoodEntry(date: Date(), photoFileName: name, status: .pending)
        store.upsertFoodEntry(entry)
        return entry
    }

    private func status(_ entry: FoodEntry) -> FoodEntryStatus? {
        store.allFoodEntries.first { $0.id == entry.id }?.status
    }

    func test_success_moves_to_needsReview_with_items() async throws {
        let entry = try addPending()
        client.analyzeResults = [.success(egg)]
        await queue.processPending()
        let saved = try XCTUnwrap(store.allFoodEntries.first { $0.id == entry.id })
        XCTAssertEqual(saved.status, .needsReview)
        XCTAssertEqual(saved.items.first?.proteinG, 6.3)
        XCTAssertEqual(saved.notes, "נראה טעים")
        XCTAssertEqual(store.proteinToday, 0, "not counted until the user confirms")
    }

    func test_unreachable_keeps_pending_and_stops() async throws {
        let first = try addPending()
        let second = try addPending()
        client.analyzeResults = [.failure(.unreachable)]
        await queue.processPending()
        XCTAssertEqual(client.analyzeCalls, 1)
        XCTAssertEqual(status(first), .pending)
        XCTAssertEqual(status(second), .pending)
        XCTAssertEqual(queue.lastError, .unreachable)
    }

    func test_unauthorized_fails_entry() async throws {
        let entry = try addPending()
        client.analyzeResults = [.failure(.unauthorized)]
        await queue.processPending()
        XCTAssertEqual(status(entry), .failed(.unauthorized))
    }

    func test_bad_output_fails_entry_and_continues() async throws {
        let first = try addPending()
        let second = try addPending()
        client.analyzeResults = [.failure(.badModelOutput), .success(egg)]
        await queue.processPending()
        XCTAssertEqual(status(first), .failed(.unreadable))
        XCTAssertEqual(status(second), .needsReview)
    }

    func test_missing_photo_fails_without_calling_bridge() async throws {
        let entry = try addPending(withPhoto: false)
        await queue.processPending()
        XCTAssertEqual(status(entry), .failed(.missingPhoto))
        XCTAssertEqual(client.analyzeCalls, 0)
    }

    func test_concurrent_calls_analyze_once() async throws {
        try addPending()
        client.analyzeResults = [.success(egg), .success(egg)]
        async let a: Void = queue.processPending()
        async let b: Void = queue.processPending()
        _ = await (a, b)
        XCTAssertEqual(client.analyzeCalls, 1)
    }

    func test_no_client_configured_changes_nothing() async throws {
        let entry = try addPending()
        let unconfigured = AnalysisQueue(store: store, photos: photos, makeClient: { nil })
        await unconfigured.processPending()
        XCTAssertEqual(status(entry), .pending)
    }
}
