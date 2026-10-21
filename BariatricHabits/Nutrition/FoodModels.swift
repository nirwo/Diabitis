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

/// Amount editing for one food row. Eating half the portion means half the protein, so it
/// keeps protein per gram — remembered separately so that typing through 0 g ("100" → "00" → "50")
/// doesn't lose it.
struct FoodAmountEdit {
    private(set) var grams: Double
    private(set) var proteinG: Double
    private var proteinPerGram: Double?

    init(item: FoodItem) {
        grams = item.grams
        proteinG = item.proteinG
        proteinPerGram = item.grams > 0 ? item.proteinG / item.grams : nil
    }

    /// Returns false (and changes nothing) when the text is not a number.
    @discardableResult
    mutating func setGrams(_ text: String) -> Bool {
        guard let newGrams = parseDecimal(text) else { return false }
        grams = newGrams
        if let proteinPerGram { proteinG = proteinPerGram * newGrams }
        return true
    }

    @discardableResult
    mutating func setProtein(_ text: String) -> Bool {
        guard let newProtein = parseDecimal(text) else { return false }
        proteinG = newProtein
        if grams > 0 { proteinPerGram = newProtein / grams }
        return true
    }
}

/// Parses a non-negative number typed with either "." or "," as the decimal separator.
func parseDecimal(_ text: String) -> Double? {
    let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
    guard let value = Double(normalized), value >= 0, value.isFinite else { return nil }
    return value
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
    /// How the user says the meal was prepared, sent with the photo. Optional, so older saves still decode.
    var cookingNote: String? = nil
    /// The cooking note the stored analysis was made with, to offer re-analysis after it changes.
    var analyzedCookingNote: String? = nil
    /// Up to three AI improvement tips from the last analysis. Optional, so older saves still decode.
    var advice: [String]? = nil

    var proteinG: Double { items.reduce(0) { $0 + $1.proteinG } }

    /// Still waiting for, or in, analysis on the Mac.
    var isAwaitingAnalysis: Bool { status == .pending || status == .analyzing }

    /// Save-time merge for a copy taken before the analysis landed: analysis fields the copy lacks
    /// come from the live entry, so saving never erases them. Items the user entered win.
    func merging(liveAnalysisFrom live: FoodEntry) -> FoodEntry {
        var merged = self
        if merged.advice?.isEmpty ?? true, let advice = live.advice, !advice.isEmpty { merged.advice = advice }
        if merged.notes?.isEmpty ?? true, let notes = live.notes, !notes.isEmpty { merged.notes = notes }
        if merged.analyzedCookingNote == nil { merged.analyzedCookingNote = live.analyzedCookingNote }
        if merged.items.isEmpty && !live.items.isEmpty { merged.items = live.items }
        return merged
    }

    /// The copy with the arrived analysis, when this copy was still waiting, the live entry has
    /// just been analyzed, and the user has not touched the form. Otherwise nil.
    func adoptingAnalysis(from live: FoodEntry, isEdited: Bool) -> FoodEntry? {
        guard !isEdited, isAwaitingAnalysis, live.status == .needsReview else { return nil }
        var adopted = self
        adopted.items = live.items
        adopted.notes = live.notes
        adopted.advice = live.advice
        adopted.status = live.status
        adopted.analyzedCookingNote = live.analyzedCookingNote
        return adopted
    }
}
