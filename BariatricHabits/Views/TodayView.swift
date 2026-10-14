import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var health: HealthManager
    @EnvironmentObject private var mealTimer: MealTimer
    @EnvironmentObject private var analysisQueue: AnalysisQueue
    @Binding var selectedTab: Int

    @State private var pendingWater: Int?
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                List {
                    if let phase = store.surgeryPhase(now: context.date) {
                        Section {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(phase.title).font(.headline)
                                Text(phase.detail).font(.subheadline).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    drinkSection(now: context.date)
                    mealsSection
                    proteinSection
                    vitaminsSection
                    habitsSection
                    activitySection
                }
            }
            .navigationTitle("היום")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("הגדרות")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { GuidelinesView() } label: { Image(systemName: "book") }
                        .accessibilityLabel("הנחיות")
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(store)
                    .environmentObject(health)
                    .environmentObject(analysisQueue)
                    .environment(\.layoutDirection, .rightToLeft)
            }
            .alert("זה זמן ההפרדה מהארוחה",
                   isPresented: Binding(get: { pendingWater != nil }, set: { if !$0 { pendingWater = nil } })) {
                Button("לרשום בכל זאת") {
                    if let ml = pendingWater { store.addWater(ml) }
                    pendingWater = nil
                }
                Button("ביטול", role: .cancel) { pendingWater = nil }
            } message: {
                Text("מומלץ לא לשתות \(store.state.settings.drinkGapMinutes) דקות לפני ואחרי ארוחה.")
            }
        }
    }

    // MARK: - Protein

    private var proteinSection: some View {
        let goal = store.state.settings.proteinGoalGrams
        let eaten = Set(store.today.foodEntries.flatMap { $0.items.map(\.name) })
        let suggestions = ProteinCalculator.suggestions(remaining: Double(goal) - store.proteinToday,
                                                        stage: store.dietStage(),
                                                        library: .bundled, eatenNames: eaten)
        return Section {
            Button { selectedTab = 4 } label: {
                ProteinProgressView(total: store.proteinToday, goal: goal)
            }
            .buttonStyle(.plain)
            ForEach(suggestions) { source in
                HStack {
                    Text(source.nameHe)
                    Spacer()
                    Text("\(source.servingText) · \(formatGrams(source.proteinPerServing)) גר'")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("חלבון")
        } footer: {
            if !suggestions.isEmpty { Text("רעיונות להשלמה, מתאימים לשלב שלך.") }
        }
    }

    // MARK: - Drinking

    @ViewBuilder
    private func drinkSection(now: Date) -> some View {
        let status = store.drinkStatus(now: now, eating: mealTimer.isRunning)
        let water = store.today.waterML
        let goal = store.state.settings.waterGoalML
        Section("שתייה") {
            HStack(spacing: 12) {
                Image(systemName: statusIcon(status))
                    .font(.title2)
                    .foregroundStyle(statusAllowsDrinking(status) ? Color.blue : Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle(status)).font(.headline)
                    Text(statusDetail(status)).font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(water) / \(goal) מ״ל")
                    Spacer()
                    Text("\(min(100, water * 100 / max(goal, 1)))%").foregroundStyle(.secondary)
                }
                ProgressView(value: Double(min(water, goal)), total: Double(max(goal, 1)))
                    .tint(.blue)
            }
            HStack {
                ForEach([50, 100, 200], id: \.self) { ml in
                    Button("+\(ml)") {
                        if statusAllowsDrinking(status) { store.addWater(ml) } else { pendingWater = ml }
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                }
                Spacer()
                Button {
                    store.addWater(-50)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .disabled(water == 0)
            }
        }
    }

    private func statusAllowsDrinking(_ status: DrinkStatus) -> Bool {
        if case .allowed = status { return true }
        return false
    }

    private func statusIcon(_ status: DrinkStatus) -> String {
        switch status {
        case .allowed: return "drop.fill"
        case .afterMeal, .beforeMeal: return "hourglass"
        case .eating: return "fork.knife"
        }
    }

    private func statusTitle(_ status: DrinkStatus) -> String {
        switch status {
        case .allowed: return "אפשר לשתות"
        case .afterMeal(let until): return "לא לשתות עד \(until.timeText)"
        case .beforeMeal(let mealAt, let name): return "\(name) ב-\(mealAt.timeText) — לא לשתות"
        case .eating: return "באמצע ארוחה — לא שותים"
        }
    }

    private func statusDetail(_ status: DrinkStatus) -> String {
        switch status {
        case .allowed(let nextStop):
            if let nextStop { return "לסיים לשתות עד \(nextStop.timeText), לקראת הארוחה הבאה" }
            return "לגימות קטנות לאורך היום"
        case .afterMeal: return "הפרדה של \(store.state.settings.drinkGapMinutes) דק' אחרי הארוחה"
        case .beforeMeal: return "הפרדה של \(store.state.settings.drinkGapMinutes) דק' לפני הארוחה"
        case .eating: return "חוזרים לשתות \(store.state.settings.drinkGapMinutes) דק' אחרי סוף הארוחה"
        }
    }

    // MARK: - Meals

    private var mealsSection: some View {
        let done = store.today.completedSlots
        let slots = store.sortedSlots
        return Section {
            ForEach(slots) { slot in
                Button {
                    store.toggleSlot(slot.id)
                } label: {
                    HStack {
                        Image(systemName: done.contains(slot.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(done.contains(slot.id) ? Color.green : Color.secondary)
                        Text(slot.name)
                        if slot.isMain {
                            Text("עיקרית").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                        }
                        Spacer()
                        Text(slot.timeText).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .foregroundStyle(.primary)
            }
            Button {
                selectedTab = 1
            } label: {
                Label("לטיימר הארוחה", systemImage: "timer")
            }
        } header: {
            Text("ארוחות \(slots.filter { done.contains($0.id) }.count)/\(slots.count)")
        }
    }

    // MARK: - Vitamins

    private var vitaminsSection: some View {
        let taken = store.today.vitaminsTaken
        let vitamins = store.sortedVitamins
        return Section("ויטמינים \(vitamins.filter { taken.contains($0.id) }.count)/\(vitamins.count)") {
            ForEach(vitamins) { vitamin in
                Button {
                    store.toggleVitamin(vitamin.id)
                } label: {
                    HStack {
                        Image(systemName: taken.contains(vitamin.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(taken.contains(vitamin.id) ? Color.green : Color.secondary)
                        Text(vitamin.name)
                        Spacer()
                        Text(vitamin.timeText).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .foregroundStyle(.primary)
            }
        }
    }

    // MARK: - Habits

    private var habitsSection: some View {
        let checked = store.today.habits
        let streak = store.streak(for: Habit.noSoda)
        return Section {
            ForEach(Habit.all) { habit in
                Button {
                    store.toggleHabit(habit.id)
                } label: {
                    HStack {
                        Image(systemName: checked.contains(habit.id) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(checked.contains(habit.id) ? Color.green : Color.secondary)
                        Label(habit.title, systemImage: habit.icon)
                    }
                }
                .foregroundStyle(.primary)
            }
        } header: {
            Text("הרגלים יומיים")
        } footer: {
            if streak > 0 {
                Text("🔥 \(streak) ימים ברצף בלי משקאות מוגזים")
            }
        }
    }

    // MARK: - Activity

    private var activitySection: some View {
        let goal = store.state.settings.stepGoal
        let planned = store.state.walkPlan.weekdays.count
        return Section("פעילות") {
            Button {
                selectedTab = 3
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("\(health.todaySteps.formatted()) צעדים", systemImage: "shoeprints.fill")
                        Spacer()
                        Text("יעד \(goal.formatted())").foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(min(health.todaySteps, goal)), total: Double(max(goal, 1)))
                        .tint(.green)
                    Text("הליכות השבוע: \(store.walksThisWeek.count)/\(planned)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
        }
    }
}
