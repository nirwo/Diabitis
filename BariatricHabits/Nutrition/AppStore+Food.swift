import Foundation

extension AppStore {
    var proteinToday: Double { ProteinCalculator.total(today.foodEntries) }

    /// Today's protein once this meal counts; a meal that already counts is not added twice.
    func projectedProteinToday(with entry: FoodEntry) -> Double {
        proteinToday + (entry.status.countsTowardGoal ? 0 : entry.proteinG)
    }

    /// Calculated target when automatic and the profile is complete, else the manual goal.
    var proteinGoal: Int {
        let settings = state.settings
        if settings.proteinTarget.mode == .automatic,
           let result = ProteinTarget.calculate(settings.proteinTarget) {
            return result.grams
        }
        return settings.proteinGoalGrams
    }

    /// Stores today's effective goal on today's log; writes only when it changed.
    func refreshTodayGoalSnapshot() {
        let key = Self.key(for: Date())
        var log = state.days[key] ?? DayLog()
        guard log.proteinGoalGrams != proteinGoal else { return }
        log.proteinGoalGrams = proteinGoal
        state.days[key] = log
    }

    /// One-time migration: past days with meals but no goal snapshot get the manual goal, which was
    /// the goal in effect before snapshots existed. Never overwrites a snapshot; one state mutation.
    func backfillGoalSnapshots(now: Date = Date()) {
        guard !state.settings.didBackfillGoalSnapshots else { return }
        var newState = state
        let todayKey = Self.key(for: now)
        for (key, log) in newState.days
        where key < todayKey && !log.foodEntries.isEmpty && log.proteinGoalGrams == nil {
            newState.days[key]?.proteinGoalGrams = newState.settings.proteinGoalGrams
        }
        newState.settings.didBackfillGoalSnapshots = true
        state = newState
    }

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
        if newKey == Self.key(for: Date()) { refreshTodayGoalSnapshot() }
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
    /// Assigns `state` only when something changed, so a normal launch never writes the file.
    func resetStaleAnalyses() {
        replaceStatuses { $0 == .analyzing ? .pending : nil }
    }

    /// After the token is fixed, meals that failed with a wrong token go back to the queue.
    /// One assignment to `state`. Returns how many were requeued.
    @discardableResult
    func requeueUnauthorized() -> Int {
        replaceStatuses { $0 == .failed(.unauthorized) ? .pending : nil }
    }

    /// Confirmable or failed meals from any day: the user must see these even after midnight.
    var entriesNeedingAttention: [FoodEntry] {
        allFoodEntries.filter { entry in
            if case .failed = entry.status { return true }
            return entry.status == .needsReview
        }
    }

    /// Meals from earlier days still waiting for (or in) analysis.
    func queuedEntriesFromEarlierDays(now: Date = Date()) -> [FoodEntry] {
        let todayKey = Self.key(for: now)
        return allFoodEntries.filter {
            ($0.status == .pending || $0.status == .analyzing) && Self.key(for: $0.date) != todayKey
        }
    }

    /// Applies `transform` to every entry status (nil = keep). Single state mutation, none if nothing changed.
    @discardableResult
    private func replaceStatuses(_ transform: (FoodEntryStatus) -> FoodEntryStatus?) -> Int {
        var days = state.days
        var changed = 0
        for (key, log) in days {
            var updated = log
            var dayChanged = false
            for index in updated.foodEntries.indices {
                guard let newStatus = transform(updated.foodEntries[index].status) else { continue }
                updated.foodEntries[index].status = newStatus
                dayChanged = true
                changed += 1
            }
            if dayChanged { days[key] = updated }
        }
        if changed > 0 { state.days = days }
        return changed
    }
}
