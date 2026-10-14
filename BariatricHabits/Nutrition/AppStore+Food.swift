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

    /// Inserts under the day the meal was eaten, or replaces the entry with the same id
    /// (moving it if its date now falls on another day). One assignment to `state`.
    func upsertFoodEntry(_ entry: FoodEntry) {
        var entry = entry
        entry.items = entry.items.map(\.sanitized)
        let newKey = Self.key(for: entry.date)
        var days = state.days
        var replacedInPlace = false
        for (key, log) in days {
            guard let index = log.foodEntries.firstIndex(where: { $0.id == entry.id }) else { continue }
            var updated = log
            if key == newKey {
                updated.foodEntries[index] = entry
                replacedInPlace = true
            } else {
                updated.foodEntries.remove(at: index)
            }
            days[key] = updated
        }
        if !replacedInPlace {
            var log = days[newKey] ?? DayLog()
            log.foodEntries.append(entry)
            days[newKey] = log
        }
        state.days = days
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
        var days = state.days
        for (key, log) in days {
            var updated = log
            for index in updated.foodEntries.indices where updated.foodEntries[index].status == .analyzing {
                updated.foodEntries[index].status = .pending
            }
            days[key] = updated
        }
        state.days = days
    }
}
