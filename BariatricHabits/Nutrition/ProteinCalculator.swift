import Foundation

enum ProteinCalculator {
    /// Upper end of the 20–30 g per-meal guidance (docs/research G5).
    static let perMealTarget = 30.0

    static func total(_ entries: [FoodEntry]) -> Double {
        entries.filter { $0.status.countsTowardGoal }.reduce(0) { $0 + $1.proteinG }
    }

    static func remaining(goal: Int, entries: [FoodEntry]) -> Double {
        max(0, Double(goal) - total(entries))
    }

    /// Stage-appropriate foods whose serving is closest to what one meal should add.
    /// Foods already eaten today go last so suggestions vary.
    static func suggestions(remaining: Double, stage: DietStage?, library: FoodLibrary,
                            eatenNames: Set<String>, limit: Int = 3) -> [ProteinSource] {
        guard remaining > 0 else { return [] }
        let target = min(remaining, perMealTarget)
        return library.sources(for: stage)
            .sorted { lhs, rhs in
                let lhsEaten = eatenNames.contains(lhs.nameHe)
                let rhsEaten = eatenNames.contains(rhs.nameHe)
                if lhsEaten != rhsEaten { return !lhsEaten }
                return abs(lhs.proteinPerServing - target) < abs(rhs.proteinPerServing - target)
            }
            .prefix(limit)
            .map { $0 }
    }
}

func formatGrams(_ value: Double) -> String {
    let rounded = (value * 10).rounded() / 10
    return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
}
