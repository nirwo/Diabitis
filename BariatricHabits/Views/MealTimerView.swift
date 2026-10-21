import SwiftUI
import UIKit

private let eatingTips = [
    "להניח את הסכו״ם על השולחן בין ביס לביס",
    "ללעוס כל ביס 20–30 פעמים, עד למרקם של מחית",
    "ביסים קטנים — בגודל של כפית",
    "חלבון קודם: להתחיל מהמנה החלבונית",
    "לעצור בתחושת השובע הראשונה",
    "לא שותים במהלך הארוחה",
    "לשבת זקוף ולאכול בלי מסכים",
]

struct MealSummary: Identifiable {
    let id = UUID()
    let record: MealRecord
    let drinkAt: Date
}

struct MealTimerView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var timer: MealTimer
    @EnvironmentObject private var analysisQueue: AnalysisQueue

    @State private var now = Date()
    @State private var selectedSlotID: UUID?
    @State private var summary: MealSummary?
    @State private var chewDoneSignaled = true
    @State private var targetSignaled = false
    @State private var confirmCancel = false
    @State private var showingMealCamera = false
    /// The meal photographed from this tab; shown until the timer finishes or is cancelled.
    @State private var mealEntryID: UUID?
    @State private var reviewing: FoodEntry?
    private let photos = PhotoStore()

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var chewSeconds: Double { Double(store.state.settings.chewSeconds) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if timer.isRunning { runningView } else { setupView }
                }
                .padding()
            }
            .navigationTitle("טיימר ארוחה")
        }
        .onReceive(ticker) { date in
            now = date
            signalMilestones()
            // Deleted, or the day has moved on: the card's meal is no longer today's.
            if mealEntryID != nil && mealEntry == nil { mealEntryID = nil }
        }
        .onAppear {
            if selectedSlotID == nil { selectedSlotID = store.suggestedSlot()?.id }
            targetSignaled = timer.elapsed(at: Date()) >= Double(timer.targetMinutes * 60)
        }
        .onChange(of: timer.isRunning) { wasRunning, isRunning in
            if wasRunning && !isRunning { mealEntryID = nil }
        }
        .sheet(item: $summary) { summary in
            MealSummaryView(summary: summary)
                .presentationDetents([.medium])
        }
        .mealPhotoCapture(isPresented: $showingMealCamera, slotName: selectedSlot?.name) { mealEntryID = $0 }
        .sheet(item: $reviewing) { entry in
            MealReviewView(entry: entry)
                .environmentObject(store)
                .environmentObject(analysisQueue)
                .environment(\.layoutDirection, .rightToLeft)
        }
    }

    // MARK: - Setup

    private var selectedSlot: MealSlot? {
        store.state.mealSlots.first { $0.id == selectedSlotID }
    }

    private var plannedMinutes: Int {
        guard let slot = selectedSlot else { return store.state.settings.mainMealMinutes }
        return slot.isMain ? store.state.settings.mainMealMinutes : store.state.settings.snackMealMinutes
    }

    private var setupView: some View {
        VStack(spacing: 20) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)

            Picker("ארוחה", selection: $selectedSlotID) {
                ForEach(store.sortedSlots) { slot in
                    Text("\(slot.name) · \(slot.timeText)").tag(Optional(slot.id))
                }
                Text("ארוחה אחרת").tag(UUID?.none)
            }
            .pickerStyle(.menu)

            Text("\(plannedMinutes) דקות")
                .font(.system(size: 44, weight: .bold, design: .rounded))
            Text("ביס, הנחת הסכו״ם ולעיסה של \(store.state.settings.chewSeconds) שניות לפני הביס הבא")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let wait = store.minutesSinceLastDrinkWarning(now: now) {
                Label("שתית לאחרונה — מומלץ לחכות עוד \(wait) דק' לפני האכילה", systemImage: "drop.triangle.fill")
                    .font(.subheadline)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("לפני שמתחילים").font(.headline)
                checklistRow("סיימתי לשתות לפחות \(store.state.settings.drinkGapMinutes) דק' לפני")
                checklistRow("צלחת קטנה וסכו״ם קטן")
                checklistRow("יושבים ליד שולחן, בלי מסכים")
                checklistRow("מתחילים מהחלבון")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))

            if let mealEntry { mealCard(mealEntry) }

            Button {
                showingMealCamera = true
            } label: {
                Label("צלם את המנה", systemImage: "camera")
                    .font(.title3.bold()).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)

            Button {
                timer.start(slot: selectedSlot, minutes: plannedMinutes)
                targetSignaled = false
                chewDoneSignaled = true
                now = Date()
            } label: {
                Text("מתחילים לאכול").font(.title3.bold()).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func checklistRow(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle").foregroundStyle(.primary)
    }

    // MARK: - Meal photo

    /// Read from today's log each time, so the card follows the analysis as it completes
    /// and disappears once the meal is deleted or is no longer today's.
    private var mealEntry: FoodEntry? {
        guard let mealEntryID else { return nil }
        return store.log(for: Date()).foodEntries.first { $0.id == mealEntryID }
    }

    private func mealCard(_ entry: FoodEntry) -> some View {
        Button { reviewing = entry } label: {
            HStack(alignment: .top, spacing: 12) {
                mealThumbnail(entry)
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.slotName ?? "המנה שצילמת").font(.headline)
                    if case .failed = entry.status {
                        Label(entry.status.labelHe, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline).foregroundStyle(.orange)
                    } else if !entry.status.labelHe.isEmpty {
                        Text(entry.status.labelHe).font(.subheadline).foregroundStyle(.orange)
                    }
                    ForEach(entry.items) { item in
                        Text("\(item.name) · \(formatGrams(item.grams)) גר'").font(.subheadline)
                    }
                    if !entry.items.isEmpty {
                        Text("+\(formatGrams(entry.proteinG)) גר' → \(formatGrams(store.projectedProteinToday(with: entry)))/\(store.proteinGoal) היום")
                            .font(.subheadline.bold())
                    }
                    AdviceView(advice: entry.advice ?? [])
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityHint("פתיחת פרטי הארוחה")
    }

    private func mealThumbnail(_ entry: FoodEntry) -> some View {
        Group {
            if let name = entry.photoFileName, let image = photos.thumbnail(for: name) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "fork.knife").foregroundStyle(.secondary)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
    }

    // MARK: - Running

    private var runningView: some View {
        let elapsed = timer.elapsed(at: now)
        let target = Double(timer.targetMinutes * 60)
        let progress = min(1, elapsed / max(target, 1))
        let reachedTarget = elapsed >= target
        let chewRemaining = timer.lastBite.map { chewSeconds - now.timeIntervalSince($0) } ?? 0
        let chewing = chewRemaining > 0
        let tip = eatingTips[Int(elapsed / 20) % eatingTips.count]

        return VStack(spacing: 22) {
            if let slot = store.state.mealSlots.first(where: { $0.id == timer.slotID }) {
                Text(slot.name).font(.title2.bold())
            }

            ZStack {
                Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 18)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(reachedTarget ? Color.green : Color.accentColor,
                            style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
                VStack(spacing: 4) {
                    Text(reachedTarget ? "+" + formatDuration(elapsed - target) : formatDuration(target - elapsed))
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(reachedTarget ? "הגעת ליעד 🎉" : "נותרו")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 250, height: 250)
            .environment(\.layoutDirection, .leftToRight)

            Text(tip)
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 50)
                .padding()
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                .animation(.easeInOut, value: tip)

            Button {
                timer.takeBite()
                chewDoneSignaled = false
                now = Date()
            } label: {
                VStack(spacing: 4) {
                    if chewing {
                        Text("לועסים לאט… \(Int(chewRemaining.rounded(.up)))")
                            .font(.title2.bold())
                        Text("הסכו״ם על השולחן").font(.caption)
                    } else {
                        Text("לקחתי ביס").font(.title2.bold())
                        Text("ביס מספר \(timer.bites + 1)").font(.caption)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(chewing ? Color.orange : Color.accentColor)
            .disabled(chewing)

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    confirmCancel = true
                } label: {
                    Text("ביטול").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    finish()
                } label: {
                    Text("סיימתי לאכול").bold().frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.green)
            }

            if let mealEntry { mealCard(mealEntry) }
        }
        .confirmationDialog("לבטל את הארוחה?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("ביטול הארוחה בלי לשמור", role: .destructive) { timer.cancel() }
        }
    }

    private func signalMilestones() {
        guard timer.isRunning else { return }
        if !chewDoneSignaled, let last = timer.lastBite, now.timeIntervalSince(last) >= chewSeconds {
            chewDoneSignaled = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        if !targetSignaled, timer.elapsed(at: now) >= Double(timer.targetMinutes * 60) {
            targetSignaled = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func finish() {
        let slots = store.state.mealSlots
        guard let record = timer.stop(slotName: { id in slots.first { $0.id == id }?.name ?? "ארוחה" }) else { return }
        store.finishMeal(record)
        let drinkAt = record.end.addingTimeInterval(TimeInterval(store.state.settings.drinkGapMinutes * 60))
        summary = MealSummary(record: record, drinkAt: drinkAt)
        selectedSlotID = store.suggestedSlot()?.id
    }
}

struct MealSummaryView: View {
    let summary: MealSummary
    @Environment(\.dismiss) private var dismiss

    private var tooFast: Bool { summary.record.duration < Double(summary.record.targetMinutes * 60) }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: tooFast ? "tortoise.fill" : "star.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(tooFast ? Color.orange : Color.green)
            Text(tooFast ? "אפשר עוד יותר לאט" : "כל הכבוד!").font(.title.bold())
            Text("\(summary.record.slotName): \(formatDuration(summary.record.duration)) דקות · \(summary.record.bites) ביסים")
                .foregroundStyle(.secondary)
            if tooFast {
                Text("היעד הוא \(summary.record.targetMinutes) דקות. בפעם הבאה — ביסים קטנים יותר ולעיסה ארוכה יותר.")
                    .multilineTextAlignment(.center)
            }
            Label("חוזרים לשתות ב-\(summary.drinkAt.timeText)", systemImage: "drop.fill")
                .font(.headline)
                .foregroundStyle(.blue)
            Text("נשלח תזכורת כשיגיע הזמן").font(.caption).foregroundStyle(.secondary)
            Button("סגירה") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .environment(\.layoutDirection, .rightToLeft)
    }
}
