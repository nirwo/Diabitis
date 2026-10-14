import SwiftUI
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

@main
struct BariatricHabitsApp: App {
    private static let notificationDelegate = NotificationDelegate()

    @StateObject private var store: AppStore
    @StateObject private var analysisQueue: AnalysisQueue
    @StateObject private var health = HealthManager()
    @StateObject private var mealTimer = MealTimer()

    init() {
        UNUserNotificationCenter.current().delegate = Self.notificationDelegate
        let store = AppStore()
        _store = StateObject(wrappedValue: store)
        _analysisQueue = StateObject(wrappedValue: AnalysisQueue(
            store: store, photos: PhotoStore(),
            makeClient: { BridgeConfig.makeClient(settings: store.state.settings) }))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(health)
                .environmentObject(mealTimer)
                .environmentObject(analysisQueue)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "he_IL"))
        }
    }
}
