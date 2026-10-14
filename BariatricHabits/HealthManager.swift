import Foundation
import HealthKit

struct DaySteps: Identifiable {
    var id: Date { date }
    let date: Date
    let steps: Int
}

@MainActor
final class HealthManager: ObservableObject {
    @Published private(set) var todaySteps = 0
    @Published private(set) var week: [DaySteps] = []
    @Published private(set) var requested = UserDefaults.standard.bool(forKey: "healthRequested")

    let isAvailable = HKHealthStore.isHealthDataAvailable()
    private let healthStore = HKHealthStore()
    private let stepType = HKQuantityType(.stepCount)

    func requestAccess() async {
        guard isAvailable else { return }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: [stepType])
            requested = true
            UserDefaults.standard.set(true, forKey: "healthRequested")
            await refresh()
        } catch {
            print("HealthKit authorization failed: \(error)")
        }
    }

    func refresh() async {
        guard isAvailable, requested else { return }
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        guard let weekStart = cal.date(byAdding: .day, value: -6, to: todayStart),
              let end = cal.date(byAdding: .day, value: 1, to: todayStart) else { return }

        let predicate = HKQuery.predicateForSamples(withStart: weekStart, end: end)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: stepType, predicate: predicate),
            options: .cumulativeSum,
            anchorDate: weekStart,
            intervalComponents: DateComponents(day: 1)
        )
        do {
            let collection: HKStatisticsCollection? = try await descriptor.result(for: healthStore)
            var days: [DaySteps] = []
            collection?.enumerateStatistics(from: weekStart, to: end) { stats, _ in
                guard stats.startDate < end else { return }
                let value = stats.sumQuantity()?.doubleValue(for: .count()) ?? 0
                days.append(DaySteps(date: stats.startDate, steps: Int(value)))
            }
            week = days
            todaySteps = days.first { cal.isDate($0.date, inSameDayAs: todayStart) }?.steps ?? 0
        } catch {
            print("HealthKit query failed: \(error)")
        }
    }

    func steps(from start: Date, to end: Date) async -> Int {
        guard isAvailable, requested else { return 0 }
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: stepType, predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
            options: .cumulativeSum
        )
        let stats: HKStatistics? = try? await descriptor.result(for: healthStore)
        return Int(stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
    }
}
