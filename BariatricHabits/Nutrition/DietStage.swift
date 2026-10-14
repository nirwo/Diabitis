import Foundation

/// Post-surgery diet stage. Day boundaries follow the generic NHS protocol
/// (docs/research G3); the user's own team overrides via settings.
enum DietStage: String, Codable, CaseIterable, Comparable, Identifiable {
    case preSurgery, liquid, puree, soft, regular

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preSurgery: "לפני הניתוח"
        case .liquid: "נוזלים"
        case .puree: "מחית"
        case .soft: "מזון רך"
        case .regular: "רגיל"
        }
    }

    private var order: Int {
        switch self {
        case .preSurgery: 0
        case .liquid: 1
        case .puree: 2
        case .soft: 3
        case .regular: 4
        }
    }

    static func < (lhs: DietStage, rhs: DietStage) -> Bool { lhs.order < rhs.order }

    static func from(surgeryDate: Date?, now: Date, calendar: Calendar = .current) -> DietStage? {
        guard let surgeryDate else { return nil }
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: surgeryDate),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<0: return .preSurgery
        case 0...14: return .liquid
        case 15...28: return .puree
        case 29...56: return .soft
        default: return .regular
        }
    }
}
