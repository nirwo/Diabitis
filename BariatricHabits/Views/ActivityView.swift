import SwiftUI
import Charts
import UIKit

struct ActivityView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var health: HealthManager
    @State private var showingWalk = false
    @State private var showingManualLog = false

    var body: some View {
        NavigationStack {
            List {
                stepsSection
                walksSection
                if !store.state.walks.isEmpty {
                    Section("הליכות אחרונות") {
                        ForEach(store.state.walks.prefix(10)) { walk in
                            HStack {
                                Image(systemName: "figure.walk").foregroundStyle(.tint)
                                Text(walk.date.formatted(.dateTime.weekday(.wide).day().month()))
                                Spacer()
                                Text("\(walk.minutes) דק'")
                                if let steps = walk.steps, steps > 0 {
                                    Text("· \(steps.formatted()) צעדים").foregroundStyle(.secondary)
                                }
                            }
                            .font(.subheadline)
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { store.state.walks[$0].id }
                            store.state.walks.removeAll { ids.contains($0.id) }
                        }
                    }
                }
            }
            .navigationTitle("פעילות")
            .refreshable { await health.refresh() }
            .fullScreenCover(isPresented: $showingWalk) {
                WalkSessionView().environmentObject(store).environmentObject(health)
            }
            .sheet(isPresented: $showingManualLog) { ManualWalkView().environmentObject(store) }
        }
    }

    private var stepsSection: some View {
        let goal = store.state.settings.stepGoal
        return Section("צעדים") {
            if !health.isAvailable {
                Text("נתוני בריאות אינם זמינים במכשיר זה.").foregroundStyle(.secondary)
            } else if !health.requested {
                Button("חיבור לנתוני הצעדים (אפליקציית בריאות)") {
                    Task { await health.requestAccess() }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(health.todaySteps.formatted())
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                        Text("צעדים היום").foregroundStyle(.secondary)
                    }
                    ProgressView(value: Double(min(health.todaySteps, goal)), total: Double(max(goal, 1)))
                        .tint(.green)
                    Text("יעד יומי: \(goal.formatted())").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                if !health.week.isEmpty {
                    Chart {
                        ForEach(health.week) { day in
                            BarMark(x: .value("יום", day.date, unit: .day),
                                    y: .value("צעדים", day.steps))
                                .foregroundStyle(day.steps >= goal ? Color.green : Color.accentColor)
                                .cornerRadius(4)
                        }
                        RuleMark(y: .value("יעד", goal))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                            .foregroundStyle(.secondary)
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                        }
                    }
                    .frame(height: 170)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var walksSection: some View {
        let plan = store.state.walkPlan
        let done = store.walksThisWeek
        let doneWeekdays = Set(done.map { Calendar.current.component(.weekday, from: $0.date) })
        return Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("השבוע: \(done.count) מתוך \(plan.weekdays.count)").font(.headline)
                    Spacer()
                    if done.count >= plan.weekdays.count && !plan.weekdays.isEmpty {
                        Text("🏆 יעד שבועי הושג").font(.caption.bold()).foregroundStyle(.green)
                    }
                }
                HStack(spacing: 6) {
                    ForEach(1...7, id: \.self) { weekday in
                        let planned = plan.weekdays.contains(weekday)
                        let walked = doneWeekdays.contains(weekday)
                        Text(hebrewWeekdayLetters[weekday - 1])
                            .font(.caption.bold())
                            .frame(width: 34, height: 34)
                            .background(walked ? Color.green : (planned ? Color.accentColor.opacity(0.2) : Color.clear),
                                        in: Circle())
                            .overlay(Circle().stroke(planned ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1))
                            .foregroundStyle(walked ? Color.white : Color.primary)
                    }
                }
                Text("מתוכנן: \(plan.durationMinutes) דק' בשעה \(plan.timeText) בימים \(plan.weekdays.sorted().map { hebrewWeekdays[$0 - 1] }.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            Button {
                showingWalk = true
            } label: {
                Label("התחלת הליכה של \(plan.durationMinutes) דק'", systemImage: "play.circle.fill")
                    .font(.headline)
            }
            Button {
                showingManualLog = true
            } label: {
                Label("רישום הליכה שכבר בוצעה", systemImage: "square.and.pencil")
            }
        } header: {
            Text("הליכות")
        } footer: {
            Text("את הימים והשעה אפשר לשנות בהגדרות. התזכורת תגיע בזמן ההליכה המתוכנן.")
        }
    }
}

struct WalkSessionView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var health: HealthManager
    @Environment(\.dismiss) private var dismiss

    @State private var start = Date()
    @State private var now = Date()
    @State private var steps = 0
    @State private var finishedSignaled = false
    @State private var confirmStop = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var target: TimeInterval { TimeInterval(store.state.walkPlan.durationMinutes * 60) }

    var body: some View {
        let elapsed = now.timeIntervalSince(start)
        let progress = min(1, elapsed / max(target, 1))
        VStack(spacing: 28) {
            Text("הליכה").font(.largeTitle.bold())
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 20)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 6) {
                    Text(formatDuration(elapsed))
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("מתוך \(store.state.walkPlan.durationMinutes):00").foregroundStyle(.secondary)
                }
            }
            .frame(width: 270, height: 270)
            .environment(\.layoutDirection, .leftToRight)

            if health.requested {
                Label("\(steps.formatted()) צעדים בהליכה", systemImage: "shoeprints.fill")
                    .font(.title3)
            }
            Text(elapsed >= target ? "כל הכבוד! השלמת את ההליכה 🎉" : "קצב נוח, נשימה רגועה, ולשתות מים בלגימות קטנות.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Spacer()

            Button {
                if elapsed >= target { save(elapsed: elapsed) } else { confirmStop = true }
            } label: {
                Text("סיום הליכה").font(.title3.bold()).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .padding(.horizontal)
        }
        .padding(.top, 40)
        .padding(.bottom)
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear {
            start = Date()
            UIApplication.shared.isIdleTimerDisabled = true
            NotificationManager.scheduleOnce(id: "walk.done", at: start.addingTimeInterval(target),
                                             title: "השלמת \(store.state.walkPlan.durationMinutes) דקות הליכה! 🎉",
                                             body: "אפשר לחזור לאפליקציה ולסיים את ההליכה.")
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            NotificationManager.cancel("walk.done")
        }
        .onReceive(ticker) { date in
            now = date
            if !finishedSignaled && date.timeIntervalSince(start) >= target {
                finishedSignaled = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            if Int(date.timeIntervalSince(start)) % 20 == 0 {
                Task { steps = await health.steps(from: start, to: date) }
            }
        }
        .confirmationDialog("לסיים לפני הזמן?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("לשמור ולסיים") { save(elapsed: now.timeIntervalSince(start)) }
            Button("לסיים בלי לשמור", role: .destructive) { dismiss() }
            Button("להמשיך ללכת", role: .cancel) {}
        }
    }

    private func save(elapsed: TimeInterval) {
        let minutes = max(1, Int(elapsed / 60))
        let startDate = start
        Task {
            let finalSteps = await health.steps(from: startDate, to: Date())
            store.logWalk(WalkRecord(date: startDate, minutes: minutes, steps: finalSteps))
            await health.refresh()
        }
        dismiss()
    }
}

struct ManualWalkView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var minutes = 60

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("מתי", selection: $date, in: ...Date())
                Stepper("משך: \(minutes) דק'", value: $minutes, in: 5...180, step: 5)
            }
            .navigationTitle("רישום הליכה")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמירה") {
                        store.logWalk(WalkRecord(date: date, minutes: minutes, steps: nil))
                        dismiss()
                    }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .presentationDetents([.medium])
    }
}
