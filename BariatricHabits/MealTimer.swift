import Foundation
import UIKit

/// Running state of the meal timer, persisted so it survives the app being closed.
@MainActor
final class MealTimer: ObservableObject {
    @Published private(set) var startDate: Date?
    @Published private(set) var targetMinutes = 15
    @Published private(set) var slotID: UUID?
    @Published private(set) var bites = 0
    @Published private(set) var lastBite: Date?

    private let defaults = UserDefaults.standard

    var isRunning: Bool { startDate != nil }

    init() {
        let start = defaults.double(forKey: "meal.start")
        if start > 0 {
            startDate = Date(timeIntervalSince1970: start)
            targetMinutes = defaults.integer(forKey: "meal.target")
            slotID = defaults.string(forKey: "meal.slot").flatMap(UUID.init(uuidString:))
            bites = defaults.integer(forKey: "meal.bites")
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }

    func elapsed(at now: Date) -> TimeInterval {
        guard let startDate else { return 0 }
        return now.timeIntervalSince(startDate)
    }

    func start(slot: MealSlot?, minutes: Int) {
        let now = Date()
        startDate = now
        targetMinutes = minutes
        slotID = slot?.id
        bites = 0
        lastBite = nil
        defaults.set(now.timeIntervalSince1970, forKey: "meal.start")
        defaults.set(minutes, forKey: "meal.target")
        defaults.set(slot?.id.uuidString, forKey: "meal.slot")
        defaults.set(0, forKey: "meal.bites")
        UIApplication.shared.isIdleTimerDisabled = true
        NotificationManager.scheduleOnce(
            id: "meal.target",
            at: now.addingTimeInterval(TimeInterval(minutes * 60)),
            title: "עברו \(minutes) דקות ⏱️",
            body: "כל הכבוד על האכילה האיטית! לעצור בתחושת השובע הראשונה."
        )
    }

    func takeBite() {
        bites += 1
        lastBite = Date()
        defaults.set(bites, forKey: "meal.bites")
    }

    /// Stops the timer and returns the finished meal, if one was running.
    func stop(slotName: (UUID?) -> String) -> MealRecord? {
        guard let startDate else { return nil }
        let record = MealRecord(slotID: slotID, slotName: slotName(slotID), start: startDate,
                                end: Date(), targetMinutes: targetMinutes, bites: bites)
        cancel()
        return record
    }

    func cancel() {
        startDate = nil
        slotID = nil
        bites = 0
        lastBite = nil
        for key in ["meal.start", "meal.target", "meal.slot", "meal.bites"] { defaults.removeObject(forKey: key) }
        UIApplication.shared.isIdleTimerDisabled = false
        NotificationManager.cancel("meal.target")
    }
}
