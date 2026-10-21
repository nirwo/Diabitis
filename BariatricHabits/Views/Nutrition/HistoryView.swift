import SwiftUI

/// Day-by-day eating history: a week strip, a date jump, and the chosen day's timeline.
struct HistoryView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var analysisQueue: AnalysisQueue
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var reviewing: FoodEntry?
    private let photos = PhotoStore()
    private let calendar = Calendar.current
    private static let daysPerWeek = 7

    private var today: Date { calendar.startOfDay(for: Date()) }

    /// The 7 days of the strip page that contains the selected day; the newest page ends today.
    private var weekDays: [Date] {
        let daysAgo = calendar.dateComponents([.day], from: selectedDay, to: today).day ?? 0
        let page = max(0, daysAgo) / Self.daysPerWeek
        let end = calendar.date(byAdding: .day, value: -page * Self.daysPerWeek, to: today) ?? today
        return (0..<Self.daysPerWeek).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: end) }
    }

    private var isOnLatestWeek: Bool { weekDays.contains(today) }

    private var summary: DaySummary {
        DayHistory.summary(for: selectedDay, log: store.log(for: selectedDay), slots: store.sortedSlots,
                           currentGoal: store.proteinGoal, now: Date())
    }

    var body: some View {
        List {
            Section {
                weekStrip
                DatePicker("קפיצה לתאריך", selection: $selectedDay, in: ...Date(), displayedComponents: .date)
            }
            let summary = summary
            Section { summaryCard(summary) }
            Section("ציר היום") {
                if summary.rows.isEmpty {
                    Text("אין ארוחות ביום הזה").foregroundStyle(.secondary)
                }
                ForEach(summary.rows) { row in rowView(row) }
            }
        }
        .navigationTitle("היסטוריה")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedDay) { _, newValue in
            let day = calendar.startOfDay(for: newValue)
            if day != newValue { selectedDay = day }
        }
        .sheet(item: $reviewing) { entry in
            MealReviewView(entry: entry)
                .environmentObject(store)
                .environmentObject(analysisQueue)
                .environment(\.layoutDirection, .rightToLeft)
        }
    }

    // MARK: Week strip

    private var weekStrip: some View {
        HStack(spacing: 4) {
            Button { shiftWeek(by: -Self.daysPerWeek) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("שבוע קודם")
                .frame(minWidth: 44, minHeight: 44)
            ForEach(weekDays, id: \.self) { day in dayButton(day) }
            Button { shiftWeek(by: Self.daysPerWeek) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("שבוע הבא")
                .disabled(isOnLatestWeek)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.borderless)
    }

    private func dayButton(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isToday = calendar.isDate(day, inSameDayAs: today)
        let weekday = calendar.component(.weekday, from: day)
        return Button { selectedDay = day } label: {
            VStack(spacing: 2) {
                Text(hebrewWeekdayLetters[weekday - 1]).font(.caption2)
                Text("\(calendar.component(.day, from: day))").font(.subheadline.bold())
                Circle().fill(isToday ? Color.accentColor : .clear).frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isSelected ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)) + (isToday ? ", היום" : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func shiftWeek(by days: Int) {
        let shifted = calendar.date(byAdding: .day, value: days, to: selectedDay) ?? selectedDay
        selectedDay = min(shifted, today)
    }

    // MARK: Summary

    private func summaryCard(_ summary: DaySummary) -> some View {
        let isCurrentGoalOnPastDay = !summary.isGoalSnapshot && !calendar.isDateInToday(summary.date)
        let goalSuffix = isCurrentGoalOnPastDay ? " · יעד נוכחי" : ""
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(formatGrams(summary.proteinG)) / \(summary.goal) גר' חלבון\(goalSuffix)").font(.headline)
            Text("\(summary.eatenSlots)/\(summary.plannedSlots) ארוחות").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Timeline

    @ViewBuilder
    private func rowView(_ row: DayTimelineRow) -> some View {
        switch row {
        case .meal(let entry):
            Button { reviewing = entry } label: { mealRow(entry).contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { delete(entry) } label: {
                        Label("מחיקה", systemImage: "trash")
                    }
                }
        case .planned(let slot, let state):
            plannedRow(slot, state)
        }
    }

    private func delete(_ entry: FoodEntry) {
        if let photo = store.deleteFoodEntry(id: entry.id) { photos.delete(photo) }
    }

    private func mealRow(_ entry: FoodEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                thumbnail(entry)
                VStack(alignment: .leading, spacing: 2) {
                    Text([entry.slotName, entry.date.timeText].compactMap { $0 }.joined(separator: " · "))
                        .font(.headline)
                    ForEach(entry.items) { item in
                        Text("\(item.name) · \(formatGrams(item.grams)) גר'").font(.subheadline)
                    }
                    if let note = entry.cookingNote, !note.isEmpty {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if entry.status.labelHe.isEmpty {
                    Text("\(formatGrams(entry.proteinG)) גר'").font(.subheadline.bold())
                } else {
                    Text(entry.status.labelHe).font(.caption).foregroundStyle(.orange)
                }
            }
            if let advice = entry.advice, !advice.isEmpty { AdviceView(advice: advice) }
        }
    }

    private func thumbnail(_ entry: FoodEntry) -> some View {
        Group {
            if let name = entry.photoFileName, let image = photos.thumbnail(for: name) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "fork.knife").foregroundStyle(.secondary)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }

    private func plannedRow(_ slot: MealSlot, _ state: PlannedSlotState) -> some View {
        let label: String
        let icon: String
        let isSkipped = state == .skipped
        switch state {
        case .skipped: (label, icon) = ("דולגה", "xmark.circle")
        case .upcoming: (label, icon) = ("בהמשך", "clock")
        case .eaten: (label, icon) = ("סומנה כנאכלה", "checkmark.circle")
        }
        return HStack {
            Text("\(slot.name) · \(slot.timeText)")
            Spacer()
            Label(label, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(isSkipped ? Color.orange : Color.secondary)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}
