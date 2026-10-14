import Foundation

extension AppStore {
    var proteinToday: Double { ProteinCalculator.total(today.foodEntries) }

    func dietStage(now: Date = Date()) -> DietStage? {
        state.settings.dietStageOverride ?? DietStage.from(surgeryDate: state.settings.surgeryDate, now: now)
    }

    var allFoodEntries: [FoodEntry] {
        state.days.values.flatMap(\.foodEntries).sorted { $0.date > $1.date }
    }

    /// Oldest first, so the queue analyzes in the order meals were eaten.
    func foodEntries(withStatus status: FoodEntryStatus) -> [FoodEntry] {
        state.days.values.flatMap(\.foodEntries)
            .filter { $0.status == status }
            .sorted { $0.date < $1.date }
    }

    /// Inserts under the day the meal was eaten, or replaces the entry with the same id.
    func upsertFoodEntry(_ entry: FoodEntry) {
        var entry = entry
        entry.items = entry.items.map(\.sanitized)
        let replacement = entry
        if updateFoodEntry(id: entry.id, { $0 = replacement }) { return }
        let key = Self.key(for: entry.date)
        var log = state.days[key] ?? DayLog()
        log.foodEntries.append(entry)
        state.days[key] = log
    }

    @discardableResult
    func updateFoodEntry(id: UUID, _ change: (inout FoodEntry) -> Void) -> Bool {
        for (key, log) in state.days {
            guard let index = log.foodEntries.firstIndex(where: { $0.id == id }) else { continue }
            var updated = log
            change(&updated.foodEntries[index])
            state.days[key] = updated
            return true
        }
        return false
    }

    /// Returns the photo file name so the caller can delete the file.
    func deleteFoodEntry(id: UUID) -> String? {
        for (key, log) in state.days {
            guard let index = log.foodEntries.firstIndex(where: { $0.id == id }) else { continue }
            var updated = log
            let removed = updated.foodEntries.remove(at: index)
            state.days[key] = updated
            return removed.photoFileName
        }
        return nil
    }

    /// An app kill during analysis leaves entries in `.analyzing`; put them back in the queue.
    func resetStaleAnalyses() {
        for entry in foodEntries(withStatus: .analyzing) {
            updateFoodEntry(id: entry.id) { $0.status = .pending }
        }
    }
}
