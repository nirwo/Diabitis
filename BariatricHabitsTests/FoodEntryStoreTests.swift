import XCTest
@testable import BariatricHabits

@MainActor
func makeTestStore() -> AppStore {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return AppStore(fileURL: dir.appendingPathComponent("state.json"))
}

@MainActor
final class FoodEntryStoreTests: XCTestCase {
    func test_upsert_files_entry_under_its_own_day() {
        let store = makeTestStore()
        let lateLastNight = Calendar.current.date(byAdding: .minute, value: -10,
                                                  to: Calendar.current.startOfDay(for: Date()))!
        let entry = FoodEntry(date: lateLastNight, photoFileName: "a.jpg", status: .pending)
        store.upsertFoodEntry(entry)
        store.updateFoodEntry(id: entry.id) { $0.status = .needsReview }  // analyzed after midnight
        XCTAssertEqual(store.log(for: lateLastNight).foodEntries.map(\.id), [entry.id])
        XCTAssertTrue(store.today.foodEntries.isEmpty)
    }

    func test_upsert_updates_existing_without_duplicating() {
        let store = makeTestStore()
        var entry = FoodEntry(date: Date(), status: .manual)
        store.upsertFoodEntry(entry)
        entry.items = [FoodItem(name: "קוטג'", grams: 100, proteinG: 11)]
        store.upsertFoodEntry(entry)
        XCTAssertEqual(store.today.foodEntries.count, 1)
        XCTAssertEqual(store.proteinToday, 11)
    }

    func test_upsert_sanitizes_item_values() {
        let store = makeTestStore()
        store.upsertFoodEntry(FoodEntry(date: Date(), items: [FoodItem(name: " x ", grams: -3, proteinG: 999)], status: .manual))
        let item = store.today.foodEntries[0].items[0]
        XCTAssertEqual(item.grams, 0)
        XCTAssertEqual(item.proteinG, FoodItem.maxProteinG)
    }

    func test_delete_returns_photo_name() {
        let store = makeTestStore()
        let entry = FoodEntry(date: Date(), photoFileName: "p.jpg", status: .pending)
        store.upsertFoodEntry(entry)
        XCTAssertEqual(store.deleteFoodEntry(id: entry.id), "p.jpg")
        XCTAssertTrue(store.today.foodEntries.isEmpty)
    }

    func test_resetStaleAnalyses_requeues_analyzing() {
        let store = makeTestStore()
        let entry = FoodEntry(date: Date(), photoFileName: "p.jpg", status: .analyzing)
        store.upsertFoodEntry(entry)
        store.resetStaleAnalyses()
        XCTAssertEqual(store.today.foodEntries[0].status, .pending)
    }

    func test_resetStaleAnalyses_without_stale_entries_does_not_publish() {
        let store = makeTestStore()
        store.upsertFoodEntry(FoodEntry(date: Date(), photoFileName: "p.jpg", status: .needsReview))
        var publishes = 0
        let cancellable = store.objectWillChange.sink { publishes += 1 }
        store.resetStaleAnalyses()
        cancellable.cancel()
        XCTAssertEqual(publishes, 0)
    }

    func test_requeueUnauthorized_moves_only_unauthorized_to_pending_in_one_change() {
        let store = makeTestStore()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let a = FoodEntry(date: Date(), photoFileName: "a.jpg", status: .failed(.unauthorized))
        let b = FoodEntry(date: yesterday, photoFileName: "b.jpg", status: .failed(.unauthorized))
        let c = FoodEntry(date: Date(), photoFileName: "c.jpg", status: .failed(.unreadable))
        let d = FoodEntry(date: Date(), photoFileName: "d.jpg", status: .confirmed)
        [a, b, c, d].forEach(store.upsertFoodEntry)
        var publishes = 0
        let cancellable = store.objectWillChange.sink { publishes += 1 }

        XCTAssertEqual(store.requeueUnauthorized(), 2)
        cancellable.cancel()

        XCTAssertEqual(publishes, 1, "single state mutation")
        let statuses = Dictionary(uniqueKeysWithValues: store.allFoodEntries.map { ($0.id, $0.status) })
        XCTAssertEqual(statuses[a.id], .pending)
        XCTAssertEqual(statuses[b.id], .pending)
        XCTAssertEqual(statuses[c.id], .failed(.unreadable))
        XCTAssertEqual(statuses[d.id], .confirmed)
        XCTAssertEqual(store.requeueUnauthorized(), 0)
    }

    func test_entries_needing_attention_include_any_day() {
        let store = makeTestStore()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let review = FoodEntry(date: yesterday, photoFileName: "a.jpg", status: .needsReview)
        let failed = FoodEntry(date: yesterday, photoFileName: "b.jpg", status: .failed(.missingPhoto))
        let oldPending = FoodEntry(date: yesterday, photoFileName: "c.jpg", status: .pending)
        let todayPending = FoodEntry(date: Date(), photoFileName: "d.jpg", status: .pending)
        let confirmed = FoodEntry(date: yesterday, status: .confirmed)
        [review, failed, oldPending, todayPending, confirmed].forEach(store.upsertFoodEntry)

        XCTAssertEqual(Set(store.entriesNeedingAttention.map(\.id)), [review.id, failed.id])
        XCTAssertEqual(store.queuedEntriesFromEarlierDays().map(\.id), [oldPending.id])
    }

    func test_dietStage_override_wins() {
        let store = makeTestStore()
        store.state.settings.surgeryDate = Calendar.current.date(byAdding: .day, value: -3, to: Date())
        XCTAssertEqual(store.dietStage(), .liquid)
        store.state.settings.dietStageOverride = .soft
        XCTAssertEqual(store.dietStage(), .soft)
    }

    func test_upsert_moves_entry_when_date_changes_day() {
        let store = makeTestStore()
        var entry = FoodEntry(date: Date(), status: .manual)
        store.upsertFoodEntry(entry)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        entry.date = yesterday
        store.upsertFoodEntry(entry)
        XCTAssertTrue(store.today.foodEntries.isEmpty)
        XCTAssertEqual(store.log(for: yesterday).foodEntries.map(\.id), [entry.id])
        XCTAssertEqual(store.allFoodEntries.count, 1)
    }
}
