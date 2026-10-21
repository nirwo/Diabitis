import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var health: HealthManager
    @Environment(\.dismiss) private var dismiss
    @State private var editingSlot: MealSlot?

    private var hasSurgeryDate: Binding<Bool> {
        Binding(
            get: { store.state.settings.surgeryDate != nil },
            set: { store.state.settings.surgeryDate = $0 ? (store.state.settings.surgeryDate ?? Date()) : nil }
        )
    }

    private var surgeryDate: Binding<Date> {
        Binding(
            get: { store.state.settings.surgeryDate ?? Date() },
            set: { store.state.settings.surgeryDate = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("ניתוח") {
                    Toggle("תאריך ניתוח", isOn: hasSurgeryDate)
                    if store.state.settings.surgeryDate != nil {
                        DatePicker("תאריך", selection: surgeryDate, displayedComponents: .date)
                    }
                }

                ProteinTargetSection(initial: store.state.settings.proteinTarget)

                Section("תזונה") {
                    Picker("שלב תזונה", selection: $store.state.settings.dietStageOverride) {
                        Text("אוטומטי לפי תאריך הניתוח").tag(DietStage?.none)
                        ForEach(DietStage.allCases) { stage in
                            Text(stage.title).tag(DietStage?.some(stage))
                        }
                    }
                }

                BridgeSettingsSection()

                Section {
                    ForEach(store.sortedSlots) { slot in
                        Button {
                            editingSlot = slot
                        } label: {
                            HStack {
                                Text(slot.name)
                                if slot.isMain { Text("· עיקרית").foregroundStyle(.secondary) }
                                Spacer()
                                Text(slot.timeText).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { store.sortedSlots[$0].id }
                        store.state.mealSlots.removeAll { ids.contains($0.id) }
                    }
                    Button {
                        editingSlot = MealSlot(name: "ארוחת ביניים", hour: 17, minute: 0, isMain: false)
                    } label: {
                        Label("הוספת ארוחה", systemImage: "plus")
                    }
                } header: {
                    Text("ארוחות (\(store.state.mealSlots.count))")
                } footer: {
                    Text("ההמלצה: 5 ארוחות קטנות ביום. לכל ארוחה תגיע תזכורת, ותזכורת לסיים לשתות לפניה.")
                }

                Section("קצב אכילה ושתייה") {
                    Stepper("ארוחה עיקרית: \(store.state.settings.mainMealMinutes) דק'",
                            value: $store.state.settings.mainMealMinutes, in: 5...40)
                    Stepper("ארוחת ביניים: \(store.state.settings.snackMealMinutes) דק'",
                            value: $store.state.settings.snackMealMinutes, in: 3...30)
                    Stepper("לעיסה בין ביסים: \(store.state.settings.chewSeconds) שנ'",
                            value: $store.state.settings.chewSeconds, in: 10...90, step: 5)
                    Stepper("הפרדת שתייה מאוכל: \(store.state.settings.drinkGapMinutes) דק'",
                            value: $store.state.settings.drinkGapMinutes, in: 10...90, step: 5)
                    Stepper("יעד שתייה: \(store.state.settings.waterGoalML) מ״ל",
                            value: $store.state.settings.waterGoalML, in: 500...3500, step: 100)
                    Toggle("תזכורות שתייה בין הארוחות", isOn: $store.state.settings.hydrationReminders)
                }

                walkSection

                Section("צעדים") {
                    Stepper("יעד יומי: \(store.state.settings.stepGoal.formatted())",
                            value: $store.state.settings.stepGoal, in: 1000...20000, step: 500)
                    if health.isAvailable && !health.requested {
                        Button("חיבור לאפליקציית בריאות") { Task { await health.requestAccess() } }
                    }
                }

                Section {
                    Button("אישור התראות") {
                        Task {
                            await NotificationManager.requestAuthorization()
                            await NotificationManager.rescheduleRecurring(state: store.state)
                        }
                    }
                    NavigationLink("המלצות והסברים") { GuidelinesView() }
                } footer: {
                    Text("המידע באפליקציה כללי ואינו מחליף את הנחיות הדיאטנית והצוות הרפואי.")
                }
            }
            .navigationTitle("הגדרות")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("סיום") { dismiss() } }
                // The decimal pad has no return key.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("סיום") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                        to: nil, from: nil, for: nil)
                    }
                }
            }
            .sheet(item: $editingSlot) { slot in
                MealSlotEditor(slot: slot) { saved in
                    if let index = store.state.mealSlots.firstIndex(where: { $0.id == saved.id }) {
                        store.state.mealSlots[index] = saved
                    } else {
                        store.state.mealSlots.append(saved)
                    }
                }
            }
        }
    }

    private var walkSection: some View {
        let plan = store.state.walkPlan
        return Section {
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { weekday in
                    let on = plan.weekdays.contains(weekday)
                    Button {
                        if on { store.state.walkPlan.weekdays.remove(weekday) } else { store.state.walkPlan.weekdays.insert(weekday) }
                    } label: {
                        Text(hebrewWeekdayLetters[weekday - 1])
                            .font(.subheadline.bold())
                            .frame(width: 36, height: 36)
                            .background(on ? Color.accentColor : Color.secondary.opacity(0.15), in: Circle())
                            .foregroundStyle(on ? Color.white : Color.primary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .frame(maxWidth: .infinity)
            DatePicker("שעה", selection: timeBinding($store.state.walkPlan.hour, $store.state.walkPlan.minute),
                       displayedComponents: .hourAndMinute)
            Stepper("משך: \(plan.durationMinutes) דק'", value: $store.state.walkPlan.durationMinutes, in: 10...120, step: 5)
        } header: {
            Text("תכנון הליכות")
        } footer: {
            if plan.weekdays.count != 3 {
                Text("ההמלצה: 3 הליכות בשבוע של שעה. כרגע נבחרו \(plan.weekdays.count) ימים.")
            } else {
                Text("3 הליכות בשבוע — מעולה. תגיע תזכורת בכל יום שנבחר.")
            }
        }
    }
}

struct MealSlotEditor: View {
    @State var slot: MealSlot
    var onSave: (MealSlot) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("שם הארוחה", text: $slot.name)
                DatePicker("שעה", selection: timeBinding($slot.hour, $slot.minute), displayedComponents: .hourAndMinute)
                Toggle("ארוחה עיקרית", isOn: $slot.isMain)
            }
            .navigationTitle(slot.name.isEmpty ? "ארוחה" : slot.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמירה") {
                        onSave(slot)
                        dismiss()
                    }
                    .disabled(slot.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .presentationDetents([.medium])
    }
}
