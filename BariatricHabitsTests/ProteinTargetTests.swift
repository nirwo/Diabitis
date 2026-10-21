import XCTest
@testable import BariatricHabits

@MainActor
final class ProteinTargetTests: XCTestCase {
    private func settings(height: Double? = 180, weight: Double? = 130) -> ProteinTargetSettings {
        var s = ProteinTargetSettings()
        s.heightCm = height
        s.weightKg = weight
        return s
    }

    func test_adjusted_default() {
        let r = ProteinTarget.calculate(settings())
        XCTAssertEqual(r?.idealKg ?? 0, 81.0, accuracy: 0.001)
        XCTAssertEqual(r?.basisKg ?? 0, 93.25, accuracy: 0.001)
        XCTAssertEqual(r?.grams, 112)
    }

    func test_ideal_basis() {
        var s = settings()
        s.basis = .ideal
        s.gramsPerKg = 1.5
        XCTAssertEqual(ProteinTarget.calculate(s)?.grams, 122)
    }

    func test_floor_applies() {
        var s = settings(height: 160, weight: 70)
        s.gramsPerKg = 1.0
        XCTAssertEqual(ProteinTarget.calculate(s)?.grams, 90)
    }

    func test_underweight_uses_current_weight() {
        XCTAssertEqual(ProteinTarget.calculate(settings(weight: 70))?.basisKg ?? 0, 70, accuracy: 0.001)
    }

    func test_incomplete_profile_falls_back() {
        XCTAssertNil(ProteinTarget.calculate(settings(height: nil)))
        let store = makeTestStore()
        store.state.settings.proteinTarget = settings(height: nil)
        store.state.settings.proteinGoalGrams = 100
        XCTAssertEqual(store.proteinGoal, 100)
    }

    func test_manual_mode_ignores_profile() {
        let store = makeTestStore()
        var s = settings()
        s.mode = .manual
        store.state.settings.proteinTarget = s
        store.state.settings.proteinGoalGrams = 105
        XCTAssertEqual(store.proteinGoal, 105)
    }

    func test_legacy_settings_keep_manual_goal() throws {
        let json = StateDecodingTests().legacyJSON
        let state = try JSONDecoder().decode(AppState.self, from: Data(json.utf8))
        XCTAssertEqual(state.settings.proteinTarget, ProteinTargetSettings())
        let store = makeTestStore()
        store.state = state
        XCTAssertEqual(store.proteinGoal, 100)
    }

    func test_snapshot_written_on_today_upsert() {
        let store = makeTestStore()
        store.state.settings.proteinTarget = settings()
        store.upsertFoodEntry(FoodEntry(date: Date(), status: .manual))
        XCTAssertEqual(store.today.proteinGoalGrams, 112)
        XCTAssertEqual(store.today.proteinGoalGrams, store.proteinGoal)
    }
}
