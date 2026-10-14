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

    func test_dietStage_override_wins() {
        let store = makeTestStore()
        store.state.settings.surgeryDate = Calendar.current.date(byAdding: .day, value: -3, to: Date())
        XCTAssertEqual(store.dietStage(), .liquid)
        store.state.settings.dietStageOverride = .soft
        XCTAssertEqual(store.dietStage(), .soft)
    }
}
