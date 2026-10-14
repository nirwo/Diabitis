import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var health: HealthManager
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("didOnboard") private var didOnboard = false
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            TodayView(selectedTab: $tab)
                .tabItem { Label("היום", systemImage: "sun.max.fill") }
                .tag(0)
            MealTimerView()
                .tabItem { Label("ארוחה", systemImage: "timer") }
                .tag(1)
            VitaminsView()
                .tabItem { Label("ויטמינים", systemImage: "pills.fill") }
                .tag(2)
            ActivityView()
                .tabItem { Label("פעילות", systemImage: "figure.walk") }
                .tag(3)
            SettingsView()
                .tabItem { Label("הגדרות", systemImage: "gearshape.fill") }
                .tag(4)
        }
        .sheet(isPresented: Binding(get: { !didOnboard }, set: { if !$0 { didOnboard = true } })) {
            OnboardingView { didOnboard = true }
                .environmentObject(store)
                .environmentObject(health)
                .environment(\.layoutDirection, .rightToLeft)
        }
        .task {
            await health.refresh()
            await NotificationManager.rescheduleRecurring(state: store.state)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await health.refresh() } }
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var health: HealthManager
    var onDone: () -> Void

    @State private var hasSurgeryDate = false
    @State private var surgeryDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ברוכים הבאים 👋").font(.title.bold())
                        Text("האפליקציה תעזור לבנות את ההרגלים שהדיאטנית המליצה עליהם — לפני ואחרי ניתוח מיני מעקף.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                Section("מה יש כאן") {
                    Label("טיימר ארוחה של 15 דק' עם קצב לעיסה", systemImage: "timer")
                    Label("5 ארוחות ביום עם תזכורות", systemImage: "fork.knife")
                    Label("הפרדה בין שתייה לאכילה", systemImage: "drop.triangle")
                    Label("תזכורות ויטמינים", systemImage: "pills")
                    Label("מעקב צעדים ו-3 הליכות של שעה בשבוע", systemImage: "figure.walk")
                    Label("בלי משקאות מוגזים — ספירת רצף", systemImage: "bubbles.and.sparkles")
                }
                Section("תאריך הניתוח") {
                    Toggle("יש תאריך ניתוח", isOn: $hasSurgeryDate)
                    if hasSurgeryDate {
                        DatePicker("תאריך", selection: $surgeryDate, displayedComponents: .date)
                    }
                }
                Section {
                    Button {
                        Task {
                            store.state.settings.surgeryDate = hasSurgeryDate ? surgeryDate : nil
                            await NotificationManager.requestAuthorization()
                            await health.requestAccess()
                            await NotificationManager.rescheduleRecurring(state: store.state)
                            onDone()
                        }
                    } label: {
                        Text("אישור התראות וצעדים, ומתחילים")
                            .frame(maxWidth: .infinity)
                            .bold()
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("המידע באפליקציה כללי ואינו מחליף את הנחיות הצוות המטפל. את כל הזמנים והיעדים אפשר לשנות בהגדרות.")
                }
            }
        }
        .interactiveDismissDisabled()
    }
}
