import Foundation

enum PlannedSlotState: Equatable {
    case eaten, skipped, upcoming
}

enum DayTimelineRow: Identifiable, Equatable {
    case meal(FoodEntry)
    case planned(MealSlot, PlannedSlotState)

    var id: String {
        switch self {
        case .meal(let entry): return entry.id.uuidString
        case .planned(let slot, _): return slot.id.uuidString
        }
    }
}

struct DaySummary: Equatable {
    let date: Date
    let proteinG: Double
    let goal: Int
    let isGoalSnapshot: Bool
    let eatenSlots: Int
    let plannedSlots: Int
    let rows: [DayTimelineRow]
}

enum DayHistory {
    /// A slot counts as skipped once this long has passed since its time.
    static let skipGraceMinutes = 60

    static func summary(for date: Date, log: DayLog, slots: [MealSlot], currentGoal: Int,
                        now: Date, calendar: Calendar = .current) -> DaySummary {
        let isToday = calendar.isDate(date, inSameDayAs: now)
        let isPast = !isToday && date < now
        let entries = log.foodEntries
        let matchedSlotIDs = matchEntries(entries, to: slots, on: date, calendar: calendar)

        var timed: [(time: Date, row: DayTimelineRow)] = entries.map { ($0.date, .meal($0)) }
        var eatenSlots = 0
        for slot in slots {
            let isMatched = matchedSlotIDs.contains(slot.id)
            let isEaten = log.completedSlots.contains(slot.id) || isMatched
            if isEaten { eatenSlots += 1 }
            let slotTime = slot.date(on: date, calendar: calendar)
            // Eaten slots are already represented by their meal rows, unless only ticked off.
            if isMatched { continue }
            let state = plannedState(isEaten: isEaten, isPast: isPast, isToday: isToday,
                                     slotTime: slotTime, now: now, calendar: calendar)
            timed.append((slotTime, .planned(slot, state)))
        }

        // Stable sort keeps meals (appended first) before planned rows at equal times.
        let rows = timed.enumerated()
            .sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }
            .map(\.element.row)

        let useSnapshot = !isToday && log.proteinGoalGrams != nil
        return DaySummary(date: date, proteinG: ProteinCalculator.total(entries),
                          goal: useSnapshot ? log.proteinGoalGrams! : currentGoal,
                          isGoalSnapshot: useSnapshot,
                          eatenSlots: eatenSlots, plannedSlots: slots.count, rows: rows)
    }

    /// Each same-day entry claims at most one slot: the nearest unclaimed slot with its name (ties go to the earlier slot).
    private static func matchEntries(_ entries: [FoodEntry], to slots: [MealSlot], on date: Date,
                                     calendar: Calendar) -> Set<UUID> {
        var claimed = Set<UUID>()
        let dayEntries = entries.filter { calendar.isDate($0.date, inSameDayAs: date) }
        for entry in dayEntries.sorted(by: { $0.date < $1.date }) {
            let nearest = slots
                .filter { $0.name == entry.slotName && !claimed.contains($0.id) }
                .map { (slot: $0, time: $0.date(on: date, calendar: calendar)) }
                .min { lhs, rhs in
                    let lhsGap = abs(lhs.time.timeIntervalSince(entry.date))
                    let rhsGap = abs(rhs.time.timeIntervalSince(entry.date))
                    return lhsGap != rhsGap ? lhsGap < rhsGap : lhs.time < rhs.time
                }
            if let nearest { claimed.insert(nearest.slot.id) }
        }
        return claimed
    }

    private static func plannedState(isEaten: Bool, isPast: Bool, isToday: Bool,
                                     slotTime: Date, now: Date, calendar: Calendar) -> PlannedSlotState {
        if isEaten { return .eaten }
        if isPast { return .skipped }
        guard isToday else { return .upcoming }
        let deadline = calendar.date(byAdding: .minute, value: skipGraceMinutes, to: slotTime) ?? slotTime
        return now >= deadline ? .skipped : .upcoming
    }
}
