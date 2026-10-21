import XCTest
@testable import BariatricHabits

final class DayHistoryTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        return calendar
    }()

    private let breakfast = MealSlot(name: "בוקר", hour: 8, minute: 0, isMain: true)
    private let snack = MealSlot(name: "ביניים", hour: 10, minute: 30, isMain: false)
    private let lunch = MealSlot(name: "צהריים", hour: 13, minute: 0, isMain: true)
    private var slots: [MealSlot] { [breakfast, snack, lunch] }

    private func time(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func entry(at date: Date, slot: String?, protein: Double = 20,
                       status: FoodEntryStatus = .confirmed) -> FoodEntry {
        FoodEntry(date: date, slotName: slot,
                  items: [FoodItem(name: "x", grams: 100, proteinG: protein)], status: status)
    }

    private func summary(log: DayLog, day: Int = 21, now: Date, currentGoal: Int = 112) -> DaySummary {
        DayHistory.summary(for: time(day, 0), log: log, slots: slots, currentGoal: currentGoal,
                           now: now, calendar: calendar)
    }

    func test_big_breakfast_then_skipped_lunch() {
        let meal = entry(at: time(21, 8, 10), slot: "בוקר")
        let result = summary(log: DayLog(foodEntries: [meal]), now: time(21, 15))
        XCTAssertEqual(result.rows, [.meal(meal), .planned(snack, .skipped), .planned(lunch, .skipped)])
        XCTAssertEqual(result.eatenSlots, 1)
        XCTAssertEqual(result.plannedSlots, 3)
    }

    func test_upcoming_today() {
        let meal = entry(at: time(21, 8, 10), slot: "בוקר")
        let result = summary(log: DayLog(foodEntries: [meal]), now: time(21, 12, 30))
        XCTAssertEqual(result.rows, [.meal(meal), .planned(snack, .skipped), .planned(lunch, .upcoming)])
    }

    func test_completed_slot_without_entry_counts_as_eaten() {
        let result = summary(log: DayLog(completedSlots: [snack.id]), now: time(21, 12, 30))
        XCTAssertTrue(result.rows.contains(.planned(snack, .eaten)))
        XCTAssertEqual(result.eatenSlots, 1)
    }

    func test_past_day_uses_snapshot_goal() {
        let result = summary(log: DayLog(proteinGoalGrams: 95), day: 20, now: time(21, 9))
        XCTAssertEqual(result.goal, 95)
        XCTAssertTrue(result.isGoalSnapshot)
    }

    func test_past_day_without_snapshot_uses_current_goal() {
        let result = summary(log: DayLog(), day: 20, now: time(21, 9))
        XCTAssertEqual(result.goal, 112)
        XCTAssertFalse(result.isGoalSnapshot)
    }

    func test_today_ignores_snapshot_goal() {
        let result = summary(log: DayLog(proteinGoalGrams: 95), now: time(21, 9))
        XCTAssertEqual(result.goal, 112)
        XCTAssertFalse(result.isGoalSnapshot)
    }

    func test_entry_with_unknown_slot_is_listed() {
        let meal = entry(at: time(21, 9), slot: "ארוחה ישנה")
        let result = summary(log: DayLog(foodEntries: [meal]), now: time(21, 9, 30))
        XCTAssertTrue(result.rows.contains(.meal(meal)))
        XCTAssertEqual(result.eatenSlots, 0)
    }

    func test_past_day_non_eaten_slots_are_skipped() {
        let result = summary(log: DayLog(), day: 20, now: time(21, 9))
        XCTAssertEqual(result.rows, [.planned(breakfast, .skipped), .planned(snack, .skipped), .planned(lunch, .skipped)])
    }

    func test_protein_counts_only_confirmed_and_manual() {
        let confirmed = entry(at: time(21, 8), slot: "בוקר", protein: 20)
        let review = entry(at: time(21, 9), slot: nil, protein: 30, status: .needsReview)
        let result = summary(log: DayLog(foodEntries: [confirmed, review]), now: time(21, 15))
        XCTAssertEqual(result.proteinG, 20)
    }
}
