import Foundation

enum FoodConfidence: String, Codable, Hashable {
    case low, medium, high
}

struct FoodItem: Codable, Identifiable, Hashable {
    static let maxGrams = 2000.0
    static let maxProteinG = 200.0

    var id = UUID()
    var name: String
    var grams: Double
    var proteinG: Double
    var confidence: FoodConfidence?

    /// Trimmed name and values clamped to physically plausible ranges.
    var sanitized: FoodItem {
        var copy = self
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.grams = min(max(grams, 0), Self.maxGrams)
        copy.proteinG = min(max(proteinG, 0), Self.maxProteinG)
        return copy
    }
}

enum AnalysisFailure: String, Codable, Hashable {
    case unauthorized, unreadable, missingPhoto
}

enum FoodEntryStatus: Codable, Hashable {
    case pending, analyzing, needsReview, confirmed, manual
    case failed(AnalysisFailure)

    var countsTowardGoal: Bool { self == .confirmed || self == .manual }

    var labelHe: String {
        switch self {
        case .pending: "ממתין לזיהוי"
        case .analyzing: "מזהה…"
        case .needsReview: "לאישור"
        case .confirmed, .manual: ""
        case .failed: "הזיהוי נכשל"
        }
    }
}

struct FoodEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var slotName: String?
    var items: [FoodItem] = []
    var photoFileName: String?
    var status: FoodEntryStatus
    var notes: String?

    var proteinG: Double { items.reduce(0) { $0 + $1.proteinG } }
}
