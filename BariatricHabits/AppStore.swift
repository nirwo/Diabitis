import Foundation
import SwiftUI

enum DrinkStatus {
    case allowed(nextStop: Date?)
    case afterMeal(until: Date)
    case beforeMeal(mealAt: Date, name: String)
    case eating
}

@MainActor
final class AppStore: ObservableObject {
    @Published var state: AppState {
        didSet {
            save()
            if oldValue.notificationSignature != state.notificationSignature {
                scheduleNotificationRefresh()
            }
        }
    }

    private let fileURL: URL
    private var rescheduleTask: Task<Void, Never>?

    nonisolated static func defaultFileURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    init(fileURL: URL = AppStore.defaultFileURL()) {
        self.fileURL = fileURL
        state = Self.loadState(from: fileURL)
    }

    /// Never silently drops saved data: an undecodable file is copied aside before defaults are used.
    private static func loadState(from url: URL) -> AppState {
        guard let data = try? Data(contentsOf: url) else { return AppState() }
        do {
            return try JSONDecoder().decode(AppState.self, from: data)
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = url.deletingLastPathComponent().appendingPathComponent("state.unreadable-\(stamp).json")
            try? FileManager.default.copyItem(at: url, to: backup)
            print("AppStore: saved state unreadable, backed up to \(backup.lastPathComponent): \(error)")
            return AppState()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func scheduleNotificationRefresh() {
        rescheduleTask?.cancel()
        rescheduleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, let self else { return }
            await NotificationManager.rescheduleRecurring(state: self.state)
        }
    }

    // MARK: - Days

    static func key(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func log(for date: Date) -> DayLog {
        state.days[Self.key(for: date)] ?? DayLog()
    }

    var today: DayLog { log(for: Date()) }

    func updateToday(_ change: (inout DayLog) -> Void) {
        let key = Self.key(for: Date())
        var log = state.days[key] ?? DayLog()
        change(&log)
        state.days[key] = log
    }

    var sortedSlots: [MealSlot] { state.mealSlots.sorted { $0.minutesOfDay < $1.minutesOfDay } }
    var sortedVitamins: [Vitamin] { state.vitamins.sorted { $0.minutesOfDay < $1.minutesOfDay } }

    // MARK: - Habits

    func toggleHabit(_ id: String) {
        updateToday { log in
            if log.habits.contains(id) { log.habits.remove(id) } else { log.habits.insert(id) }
        }
    }

    func streak(for habit: String) -> Int {
        let cal = Calendar.current
        var day = Date()
        if !log(for: day).habits.contains(habit) {
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        var count = 0
        while log(for: day).habits.contains(habit) {
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    // MARK: - Vitamins

    func toggleVitamin(_ id: UUID) {
        updateToday { log in
            if log.vitaminsTaken.contains(id) { log.vitaminsTaken.remove(id) } else { log.vitaminsTaken.insert(id) }
        }
    }

    // MARK: - Meals

    func toggleSlot(_ id: UUID) {
        updateToday { log in
            if log.completedSlots.contains(id) { log.completedSlots.remove(id) } else { log.completedSlots.insert(id) }
        }
    }

    func finishMeal(_ record: MealRecord) {
        updateToday { log in
            log.meals.append(record)
            if let slot = record.slotID { log.completedSlots.insert(slot) }
        }
        state.lastMealEnd = record.end
        let drinkAt = record.end.addingTimeInterval(TimeInterval(state.settings.drinkGapMinutes * 60))
        NotificationManager.scheduleOnce(
            id: "drink.allowed",
            at: drinkAt,
            title: "אפשר לחזור לשתות 💧",
            body: "עברו \(state.settings.drinkGapMinutes) דקות מסוף הארוחה. לשתות בלגימות קטנות ולאט."
        )
    }

    /// The incomplete slot whose time is closest to now.
    func suggestedSlot(now: Date = Date()) -> MealSlot? {
        let done = today.completedSlots
        return sortedSlots
            .filter { !done.contains($0.id) }
            .min { abs($0.date(on: now).timeIntervalSince(now)) < abs($1.date(on: now).timeIntervalSince(now)) }
    }

    func nextUpcomingSlot(now: Date = Date()) -> MealSlot? {
        let done = today.completedSlots
        return sortedSlots.first { !done.contains($0.id) && $0.date(on: now) > now }
    }

    // MARK: - Drinking

    func addWater(_ ml: Int) {
        updateToday { $0.waterML = max(0, $0.waterML + ml) }
        if ml > 0 { state.lastWaterAt = Date() }
    }

    func drinkStatus(now: Date, eating: Bool) -> DrinkStatus {
        if eating { return .eating }
        let gap = TimeInterval(state.settings.drinkGapMinutes * 60)
        if let end = state.lastMealEnd, now < end.addingTimeInterval(gap) {
            return .afterMeal(until: end.addingTimeInterval(gap))
        }
        if let next = nextUpcomingSlot(now: now) {
            let mealAt = next.date(on: now)
            if now >= mealAt.addingTimeInterval(-gap) {
                return .beforeMeal(mealAt: mealAt, name: next.name)
            }
            return .allowed(nextStop: mealAt.addingTimeInterval(-gap))
        }
        return .allowed(nextStop: nil)
    }

    /// Minutes still to wait before eating, if the user drank too recently.
    func minutesSinceLastDrinkWarning(now: Date = Date()) -> Int? {
        guard let last = state.lastWaterAt else { return nil }
        let gap = TimeInterval(state.settings.drinkGapMinutes * 60)
        let remaining = last.addingTimeInterval(gap).timeIntervalSince(now)
        return remaining > 0 ? Int((remaining / 60).rounded(.up)) : nil
    }

    // MARK: - Walks

    static var israelCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 1
        return cal
    }

    var walksThisWeek: [WalkRecord] {
        guard let week = Self.israelCalendar.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return state.walks.filter { week.contains($0.date) }
    }

    func logWalk(_ walk: WalkRecord) {
        state.walks.append(walk)
        state.walks.sort { $0.date > $1.date }
    }

    // MARK: - Surgery phase

    func surgeryPhase(now: Date = Date()) -> (title: String, detail: String)? {
        guard let surgery = state.settings.surgeryDate else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: surgery), to: cal.startOfDay(for: now)).day ?? 0
        if days < 0 {
            return ("עוד \(-days) ימים לניתוח",
                    "זה הזמן לתרגל את ההרגלים החדשים: אכילה איטית, לעיסה, הפרדת שתייה ובלי מוגזים.")
        }
        if days == 0 { return ("יום הניתוח", "בהצלחה! לפעול לפי הנחיות הצוות הרפואי.") }
        let stage = DietStage.from(surgeryDate: surgery, now: now, calendar: cal) ?? .regular
        let stageText = stage == .regular ? "שלב משוער: תזונה רגילה ומותאמת" : "שלב משוער: \(stage.title)"
        return ("יום \(days) אחרי הניתוח", "\(stageText) — יש לפעול לפי ההנחיות של הדיאטנית שלך.")
    }
}
