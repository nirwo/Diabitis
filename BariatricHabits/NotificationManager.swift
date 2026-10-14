import Foundation
import UserNotifications

enum NotificationManager {
    private static var center: UNUserNotificationCenter { .current() }

    /// Prefix for notifications that are rebuilt whenever the schedule changes.
    private static let recurringPrefix = "r."

    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func scheduleOnce(id: String, at date: Date, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func cancel(_ id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    static func rescheduleRecurring(state: AppState) async {
        let pending = await center.pendingNotificationRequests()
        let old = pending.map(\.identifier).filter { $0.hasPrefix(recurringPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)

        let gap = state.settings.drinkGapMinutes

        // Meals + "stop drinking" before each meal
        for slot in state.mealSlots {
            let minutes = slot.isMain ? state.settings.mainMealMinutes : state.settings.snackMealMinutes
            await add(id: "r.meal.\(slot.id)",
                      title: "\(slot.name) 🍽️",
                      body: "להפעיל את טיימר הארוחה (\(minutes) דק'), ביסים קטנים ולעיסה איטית.",
                      minutesOfDay: slot.minutesOfDay)
            await add(id: "r.stopdrink.\(slot.id)",
                      title: "עוד \(gap) דק' \(slot.name)",
                      body: "זה הזמן לסיים לשתות עד אחרי הארוחה.",
                      minutesOfDay: slot.minutesOfDay - gap)
        }

        // Vitamins
        for vitamin in state.vitamins {
            let dose = vitamin.dose.isEmpty ? "" : " — \(vitamin.dose)"
            await add(id: "r.vit.\(vitamin.id)",
                      title: "תזכורת ויטמינים 💊",
                      body: "\(vitamin.name)\(dose)",
                      minutesOfDay: vitamin.minutesOfDay)
        }

        // Walks (weekly)
        for weekday in state.walkPlan.weekdays {
            var dc = DateComponents()
            dc.weekday = weekday
            dc.hour = state.walkPlan.hour
            dc.minute = state.walkPlan.minute
            await add(id: "r.walk.\(weekday)",
                      title: "זמן הליכה 🚶",
                      body: "\(state.walkPlan.durationMinutes) דקות של הליכה מחכות לך. לקחת מים ולצאת לדרך!",
                      trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: true))
        }

        // Hydration reminders, skipped around meal windows
        if state.settings.hydrationReminders {
            let blocked = state.mealSlots.map { slot -> ClosedRange<Int> in
                let length = slot.isMain ? state.settings.mainMealMinutes : state.settings.snackMealMinutes
                return (slot.minutesOfDay - gap)...(slot.minutesOfDay + length + gap)
            }
            for minutes in stride(from: 9 * 60, through: 21 * 60, by: 60) where !blocked.contains(where: { $0.contains(minutes) }) {
                await add(id: "r.water.\(minutes)",
                          title: "זמן ללגימות מים 💧",
                          body: "לשתות לאט, בלגימות קטנות. רחוק מספיק מהארוחות.",
                          minutesOfDay: minutes)
            }
        }
    }

    private static func add(id: String, title: String, body: String, minutesOfDay: Int) async {
        let m = ((minutesOfDay % 1440) + 1440) % 1440
        var dc = DateComponents()
        dc.hour = m / 60
        dc.minute = m % 60
        await add(id: id, title: title, body: body,
                  trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: true))
    }

    private static func add(id: String, title: String, body: String, trigger: UNNotificationTrigger) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
