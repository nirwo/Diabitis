import XCTest
@testable import BariatricHabits

final class ProteinCalculatorTests: XCTestCase {
    private func source(_ id: String, _ protein: Double, _ stage: DietStage = .puree) -> ProteinSource {
        ProteinSource(id: id, nameHe: id, servingText: "", servingGrams: 100, proteinPerServing: protein,
                      proteinPer100g: protein, minStage: stage, note: "", sourceURL: URL(string: "https://x.org")!)
    }

    private lazy var library = FoodLibrary(
        sources: [source("milk", 8.4, .liquid), source("cottage", 11), source("turkey", 18.1),
                  source("cod", 18.2), source("chicken", 18.6), source("beef", 17.5, .regular)],
        recipes: [], rules: [])

    private func entry(_ protein: Double, _ status: FoodEntryStatus) -> FoodEntry {
        FoodEntry(date: Date(), items: [FoodItem(name: "x", grams: 100, proteinG: protein)], status: status)
    }

    func test_total_counts_only_confirmed_and_manual() {
        let entries = [entry(20, .confirmed), entry(10, .manual), entry(50, .needsReview), entry(40, .pending)]
        XCTAssertEqual(ProteinCalculator.total(entries), 30)
    }

    func test_remaining_never_negative() {
        XCTAssertEqual(ProteinCalculator.remaining(goal: 100, entries: [entry(30, .confirmed)]), 70)
        XCTAssertEqual(ProteinCalculator.remaining(goal: 100, entries: [entry(130, .confirmed)]), 0)
    }

    func test_no_suggestions_when_goal_reached() {
        XCTAssertTrue(ProteinCalculator.suggestions(remaining: 0, stage: .puree, library: library, eatenNames: []).isEmpty)
    }

    func test_suggestions_closest_to_target_within_stage() {
        let ids = ProteinCalculator.suggestions(remaining: 18, stage: .puree, library: library, eatenNames: []).map(\.id)
        XCTAssertEqual(ids, ["turkey", "cod", "chicken"])
    }

    func test_suggestions_target_caps_at_one_meal() {
        let first = ProteinCalculator.suggestions(remaining: 90, stage: .regular, library: library, eatenNames: []).first
        XCTAssertEqual(first?.id, "chicken", "closest to 30 g, not to 90 g")
    }

    func test_suggestions_respect_stage() {
        let ids = ProteinCalculator.suggestions(remaining: 18, stage: .liquid, library: library, eatenNames: []).map(\.id)
        XCTAssertEqual(ids, ["milk"])
    }

    func test_suggestions_prefer_foods_not_eaten_today() {
        let ids = ProteinCalculator.suggestions(remaining: 18, stage: .puree, library: library, eatenNames: ["turkey"]).map(\.id)
        XCTAssertEqual(ids, ["cod", "chicken", "cottage"])
    }

    func test_formatGrams() {
        XCTAssertEqual(formatGrams(11), "11")
        XCTAssertEqual(formatGrams(16.575), "16.6")
    }
}
