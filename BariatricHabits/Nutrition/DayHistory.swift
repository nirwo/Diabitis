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
        let entrySlotNames = Set(entries.filter { calendar.isDate($0.date, inSameDayAs: date) }.compactMap(\.slotName))

        var timed: [(time: Date, row: DayTimelineRow)] = entries.map { ($0.date, .meal($0)) }
        var eatenSlots = 0
        for slot in slots {
            let isEaten = log.completedSlots.contains(slot.id) || entrySlotNames.contains(slot.name)
            if isEaten { eatenSlots += 1 }
            let slotTime = slot.date(on: date, calendar: calendar)
            // Eaten slots are already represented by their meal rows, unless only ticked off.
            if isEaten && entrySlotNames.contains(slot.name) { continue }
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

    private static func plannedState(isEaten: Bool, isPast: Bool, isToday: Bool,
                                     slotTime: Date, now: Date, calendar: Calendar) -> PlannedSlotState {
        if isEaten { return .eaten }
        if isPast { return .skipped }
        guard isToday else { return .upcoming }
        let deadline = calendar.date(byAdding: .minute, value: skipGraceMinutes, to: slotTime) ?? slotTime
        return now >= deadline ? .skipped : .upcoming
    }
}
