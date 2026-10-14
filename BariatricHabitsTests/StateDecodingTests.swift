import XCTest
@testable import BariatricHabits

@MainActor
final class StateDecodingTests: XCTestCase {
    /// JSON exactly as the shipped app (commit e11818b) writes it — no nutrition keys.
    private let legacyJSON = """
    {"settings":{"mainMealMinutes":20,"snackMealMinutes":10,"chewSeconds":30,"drinkGapMinutes":30,
      "waterGoalML":2000,"stepGoal":7000,"hydrationReminders":false},
     "mealSlots":[],"vitamins":[],
     "walkPlan":{"weekdays":[1],"hour":18,"minute":0,"durationMinutes":60},
     "days":{"2026-10-13":{"meals":[],"completedSlots":[],"vitaminsTaken":[],"waterML":750,"habits":["noSoda"]}},
     "walks":[]}
    """

    func test_legacy_state_decodes_without_losing_values() throws {
        let state = try JSONDecoder().decode(AppState.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(state.settings.mainMealMinutes, 20)
        XCTAssertEqual(state.settings.waterGoalML, 2000)
        XCTAssertEqual(state.settings.stepGoal, 7000)
        XCTAssertFalse(state.settings.hydrationReminders)
        XCTAssertEqual(state.settings.proteinGoalGrams, 100)
        XCTAssertNil(state.settings.dietStageOverride)
        XCTAssertTrue(state.mealSlots.isEmpty, "saved empty list must not be replaced by defaults")
        XCTAssertEqual(state.days["2026-10-13"]?.waterML, 750)
        XCTAssertEqual(state.days["2026-10-13"]?.habits, ["noSoda"])
        XCTAssertEqual(state.days["2026-10-13"]?.foodEntries, [])
    }

    func test_new_state_round_trips() throws {
        var state = AppState()
        state.settings.proteinGoalGrams = 110
        state.settings.dietStageOverride = .soft
        state.settings.bridgeURL = "http://100.64.0.1:8787"
        var log = DayLog()
        log.foodEntries = [FoodEntry(date: Date(timeIntervalSince1970: 1_800_000_000),
                                     items: [FoodItem(name: "ביצה", grams: 50, proteinG: 6.3, confidence: .high)],
                                     photoFileName: "a.jpg", status: .failed(.unreadable))]
        state.days["2027-01-15"] = log
        let decoded = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.settings.proteinGoalGrams, 110)
        XCTAssertEqual(decoded.settings.dietStageOverride, .soft)
        XCTAssertEqual(decoded.days["2027-01-15"]?.foodEntries, log.foodEntries)
    }

    func test_unreadable_state_file_is_backed_up_not_overwritten() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("state.json")
        try Data("not json".utf8).write(to: file)

        _ = AppStore(fileURL: file)

        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("state.unreadable-") }
        XCTAssertEqual(backups.count, 1)
    }

    func test_food_entry_protein_and_goal_counting() {
        let items = [FoodItem(name: "a", grams: 100, proteinG: 11), FoodItem(name: "b", grams: 50, proteinG: 6.3)]
        XCTAssertEqual(FoodEntry(date: Date(), items: items, status: .confirmed).proteinG, 17.3, accuracy: 0.001)
        XCTAssertTrue(FoodEntryStatus.confirmed.countsTowardGoal)
        XCTAssertTrue(FoodEntryStatus.manual.countsTowardGoal)
        XCTAssertFalse(FoodEntryStatus.needsReview.countsTowardGoal)
        XCTAssertFalse(FoodEntryStatus.failed(.unreadable).countsTowardGoal)
    }

    func test_sanitized_clamps_and_trims() {
        let item = FoodItem(name: "  טונה ", grams: -5, proteinG: 900).sanitized
        XCTAssertEqual(item.name, "טונה")
        XCTAssertEqual(item.grams, 0)
        XCTAssertEqual(item.proteinG, FoodItem.maxProteinG)
    }
}
