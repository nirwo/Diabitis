import Foundation

struct MealSlot: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var hour: Int
    var minute: Int
    var isMain: Bool

    var minutesOfDay: Int { hour * 60 + minute }
    var timeText: String { String(format: "%02d:%02d", hour, minute) }

    func date(on day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}

struct Vitamin: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var dose: String
    var hour: Int
    var minute: Int
    var note: String

    var minutesOfDay: Int { hour * 60 + minute }
    var timeText: String { String(format: "%02d:%02d", hour, minute) }
}

struct MealRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var slotID: UUID?
    var slotName: String
    var start: Date
    var end: Date
    var targetMinutes: Int
    var bites: Int

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct WalkRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var minutes: Int
    var steps: Int?
}

struct WalkPlan: Codable, Hashable {
    /// Calendar weekdays: 1 = Sunday ... 7 = Saturday
    var weekdays: Set<Int> = [1, 3, 5]
    var hour: Int = 18
    var minute: Int = 0
    var durationMinutes: Int = 60

    var timeText: String { String(format: "%02d:%02d", hour, minute) }
}

struct AppSettings: Codable, Hashable {
    var surgeryDate: Date?
    var mainMealMinutes = 15
    var snackMealMinutes = 10
    var chewSeconds = 30
    var drinkGapMinutes = 30
    var waterGoalML = 1500
    var stepGoal = 6000
    var hydrationReminders = true
    var proteinGoalGrams = 100
    var proteinTarget = ProteinTargetSettings()
    var dietStageOverride: DietStage?
    var bridgeURL: String?
    /// Set once past days got the goal snapshot they were missing (see `backfillGoalSnapshots`).
    var didBackfillGoalSnapshots = false
}

struct DayLog: Codable, Hashable {
    var meals: [MealRecord] = []
    var completedSlots: Set<UUID> = []
    var vitaminsTaken: Set<UUID> = []
    var waterML = 0
    var habits: Set<String> = []
    var foodEntries: [FoodEntry] = []
    /// The effective protein goal when the day was last touched; history keeps the goal of its day.
    var proteinGoalGrams: Int?
}

struct AppState: Codable {
    var settings = AppSettings()
    var mealSlots: [MealSlot] = AppState.defaultMealSlots
    var vitamins: [Vitamin] = AppState.defaultVitamins
    var walkPlan = WalkPlan()
    var days: [String: DayLog] = [:]
    var walks: [WalkRecord] = []
    var lastMealEnd: Date?
    var lastWaterAt: Date?

    static let defaultMealSlots: [MealSlot] = [
        MealSlot(name: "ארוחת בוקר", hour: 8, minute: 0, isMain: true),
        MealSlot(name: "ארוחת ביניים", hour: 10, minute: 30, isMain: false),
        MealSlot(name: "ארוחת צהריים", hour: 13, minute: 0, isMain: true),
        MealSlot(name: "ארוחת ביניים", hour: 16, minute: 0, isMain: false),
        MealSlot(name: "ארוחת ערב", hour: 19, minute: 0, isMain: true),
    ]

    static let defaultVitamins: [Vitamin] = [
        Vitamin(name: "מולטי-ויטמין", dose: "", hour: 9, minute: 0, note: "לפי המלצת הדיאטנית"),
        Vitamin(name: "סידן ציטרט", dose: "", hour: 14, minute: 0, note: "להפריד מהברזל בשעתיים לפחות"),
        Vitamin(name: "ברזל", dose: "", hour: 20, minute: 0, note: "להפריד מהסידן בשעתיים לפחות"),
        Vitamin(name: "ויטמין B12", dose: "", hour: 9, minute: 0, note: ""),
        Vitamin(name: "ויטמין D", dose: "", hour: 9, minute: 0, note: ""),
    ]

    /// Fields that affect recurring notifications.
    var notificationSignature: [AnyHashable] {
        [mealSlots, vitamins, walkPlan, settings.drinkGapMinutes,
         settings.hydrationReminders, settings.mainMealMinutes]
    }
}

struct Habit: Identifiable {
    let id: String
    let title: String
    let icon: String

    static let noSoda = "noSoda"

    static let all: [Habit] = [
        Habit(id: noSoda, title: "בלי משקאות מוגזים", icon: "bubbles.and.sparkles"),
        Habit(id: "separate", title: "הפרדתי בין שתייה לאכילה", icon: "drop.triangle"),
        Habit(id: "slow", title: "אכלתי לאט, בלי למהר", icon: "tortoise"),
        Habit(id: "chew", title: "לעסתי כל ביס היטב", icon: "mouth"),
        Habit(id: "protein", title: "התחלתי כל ארוחה בחלבון", icon: "fork.knife"),
        Habit(id: "noStraw", title: "שתיתי בלגימות קטנות, בלי קש", icon: "cup.and.saucer"),
    ]
}

let hebrewWeekdays = ["ראשון", "שני", "שלישי", "רביעי", "חמישי", "שישי", "שבת"]
let hebrewWeekdayLetters = ["א׳", "ב׳", "ג׳", "ד׳", "ה׳", "ו׳", "ש׳"]

extension Date {
    var timeText: String { formatted(date: .omitted, time: .shortened) }
}

func formatDuration(_ interval: TimeInterval) -> String {
    let total = max(0, Int(interval.rounded()))
    return String(format: "%d:%02d", total / 60, total % 60)
}

// MARK: - Lossless decoding
// Every field falls back to its default when its key is missing, so adding a field
// never makes AppStore discard the user's saved data. A key that is present but holds a
// malformed value still fails the whole decode; AppStore then backs the file up before
// using defaults (and refuses to save if the backup fails).

extension AppSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        surgeryDate = try c.decodeIfPresent(Date.self, forKey: .surgeryDate)
        mainMealMinutes = try c.decodeIfPresent(Int.self, forKey: .mainMealMinutes) ?? d.mainMealMinutes
        snackMealMinutes = try c.decodeIfPresent(Int.self, forKey: .snackMealMinutes) ?? d.snackMealMinutes
        chewSeconds = try c.decodeIfPresent(Int.self, forKey: .chewSeconds) ?? d.chewSeconds
        drinkGapMinutes = try c.decodeIfPresent(Int.self, forKey: .drinkGapMinutes) ?? d.drinkGapMinutes
        waterGoalML = try c.decodeIfPresent(Int.self, forKey: .waterGoalML) ?? d.waterGoalML
        stepGoal = try c.decodeIfPresent(Int.self, forKey: .stepGoal) ?? d.stepGoal
        hydrationReminders = try c.decodeIfPresent(Bool.self, forKey: .hydrationReminders) ?? d.hydrationReminders
        proteinGoalGrams = try c.decodeIfPresent(Int.self, forKey: .proteinGoalGrams) ?? d.proteinGoalGrams
        proteinTarget = try c.decodeIfPresent(ProteinTargetSettings.self, forKey: .proteinTarget) ?? d.proteinTarget
        dietStageOverride = try c.decodeIfPresent(DietStage.self, forKey: .dietStageOverride)
        bridgeURL = try c.decodeIfPresent(String.self, forKey: .bridgeURL)
        didBackfillGoalSnapshots = try c.decodeIfPresent(Bool.self, forKey: .didBackfillGoalSnapshots)
            ?? d.didBackfillGoalSnapshots
    }
}

extension DayLog {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        meals = try c.decodeIfPresent([MealRecord].self, forKey: .meals) ?? []
        completedSlots = try c.decodeIfPresent(Set<UUID>.self, forKey: .completedSlots) ?? []
        vitaminsTaken = try c.decodeIfPresent(Set<UUID>.self, forKey: .vitaminsTaken) ?? []
        waterML = try c.decodeIfPresent(Int.self, forKey: .waterML) ?? 0
        habits = try c.decodeIfPresent(Set<String>.self, forKey: .habits) ?? []
        foodEntries = try c.decodeIfPresent([FoodEntry].self, forKey: .foodEntries) ?? []
        proteinGoalGrams = try c.decodeIfPresent(Int.self, forKey: .proteinGoalGrams)
    }
}

extension AppState {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppState()
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? d.settings
        mealSlots = try c.decodeIfPresent([MealSlot].self, forKey: .mealSlots) ?? d.mealSlots
        vitamins = try c.decodeIfPresent([Vitamin].self, forKey: .vitamins) ?? d.vitamins
        walkPlan = try c.decodeIfPresent(WalkPlan.self, forKey: .walkPlan) ?? d.walkPlan
        days = try c.decodeIfPresent([String: DayLog].self, forKey: .days) ?? [:]
        walks = try c.decodeIfPresent([WalkRecord].self, forKey: .walks) ?? []
        lastMealEnd = try c.decodeIfPresent(Date.self, forKey: .lastMealEnd)
        lastWaterAt = try c.decodeIfPresent(Date.self, forKey: .lastWaterAt)
    }
}
