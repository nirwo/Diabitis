import XCTest
@testable import BariatricHabits

@MainActor
final class GoalSnapshotBackfillTests: XCTestCase {
    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Date())!
    }

    private func meal(on date: Date) -> FoodEntry {
        FoodEntry(date: date, items: [FoodItem(name: "קוטג'", grams: 100, proteinG: 11)], status: .confirmed)
    }

    private func seeded() -> AppStore {
        let store = makeTestStore()
        store.state.settings.proteinGoalGrams = 100
        store.state.days[AppStore.key(for: day(-3))] = DayLog(foodEntries: [meal(on: day(-3))])
        store.state.days[AppStore.key(for: day(-2))] = DayLog(waterML: 500)
        store.state.days[AppStore.key(for: day(-1))] = DayLog(foodEntries: [meal(on: day(-1))], proteinGoalGrams: 85)
        store.state.days[AppStore.key(for: day(0))] = DayLog(foodEntries: [meal(on: day(0))])
        return store
    }

    func test_backfills_past_days_with_entries_only() {
        let store = seeded()
        store.backfillGoalSnapshots()
        XCTAssertEqual(store.log(for: day(-3)).proteinGoalGrams, 100)
        XCTAssertNil(store.log(for: day(-2)).proteinGoalGrams, "no meals, nothing to label")
        XCTAssertNil(store.log(for: day(0)).proteinGoalGrams, "today is not backfilled")
        XCTAssertTrue(store.state.settings.didBackfillGoalSnapshots)
    }

    func test_never_overwrites_an_existing_snapshot() {
        let store = seeded()
        store.backfillGoalSnapshots()
        XCTAssertEqual(store.log(for: day(-1)).proteinGoalGrams, 85)
    }

    func test_runs_once() {
        let store = seeded()
        store.backfillGoalSnapshots()
        store.state.days[AppStore.key(for: day(-4))] = DayLog(foodEntries: [meal(on: day(-4))])
        store.state.settings.proteinGoalGrams = 120
        store.backfillGoalSnapshots()
        XCTAssertNil(store.log(for: day(-4)).proteinGoalGrams)
        XCTAssertEqual(store.log(for: day(-3)).proteinGoalGrams, 100)
    }

    func test_backfill_uses_manual_goal_even_in_automatic_mode() {
        let store = seeded()
        store.state.settings.proteinTarget.mode = .automatic
        store.state.settings.proteinTarget.heightCm = 180
        store.state.settings.proteinTarget.weightKg = 130
        store.backfillGoalSnapshots()
        XCTAssertEqual(store.log(for: day(-3)).proteinGoalGrams, 100)
    }

    func test_flag_decodes_as_false_from_older_settings() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"proteinGoalGrams":100}"#.utf8))
        XCTAssertFalse(settings.didBackfillGoalSnapshots)
    }
}
