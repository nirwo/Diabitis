import Foundation

enum ProteinTargetMode: String, Codable {
    case automatic, manual
}

enum ProteinWeightBasis: String, Codable, CaseIterable {
    case ideal, adjusted
}

struct ProteinTargetSettings: Codable, Hashable {
    var mode: ProteinTargetMode = .automatic
    var heightCm: Double?
    var weightKg: Double?
    var weightUpdated: Date?
    var basis: ProteinWeightBasis = .adjusted
    var adjustmentFactor: Double = 0.25
    var gramsPerKg: Double = 1.2
    var floorGrams: Int = 90

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ProteinTargetSettings()
        mode = try c.decodeIfPresent(ProteinTargetMode.self, forKey: .mode) ?? d.mode
        heightCm = try c.decodeIfPresent(Double.self, forKey: .heightCm)
        weightKg = try c.decodeIfPresent(Double.self, forKey: .weightKg)
        weightUpdated = try c.decodeIfPresent(Date.self, forKey: .weightUpdated)
        basis = try c.decodeIfPresent(ProteinWeightBasis.self, forKey: .basis) ?? d.basis
        adjustmentFactor = try c.decodeIfPresent(Double.self, forKey: .adjustmentFactor) ?? d.adjustmentFactor
        gramsPerKg = try c.decodeIfPresent(Double.self, forKey: .gramsPerKg) ?? d.gramsPerKg
        floorGrams = try c.decodeIfPresent(Int.self, forKey: .floorGrams) ?? d.floorGrams
    }
}

struct ProteinTargetResult: Equatable {
    let idealKg: Double
    let basisKg: Double
    let grams: Int
}

enum ProteinTarget {
    private static let idealBmi = 25.0

    /// nil when height or weight is missing. For the dietitian to review.
    static func calculate(_ s: ProteinTargetSettings) -> ProteinTargetResult? {
        guard let heightCm = s.heightCm, let weightKg = s.weightKg else { return nil }
        let heightM = heightCm / 100
        let idealKg = idealBmi * heightM * heightM
        let basisKg: Double
        switch s.basis {
        case .ideal:
            basisKg = idealKg
        case .adjusted:
            basisKg = weightKg < idealKg ? weightKg : idealKg + s.adjustmentFactor * (weightKg - idealKg)
        }
        let grams = max(s.floorGrams, Int((basisKg * s.gramsPerKg).rounded()))
        return ProteinTargetResult(idealKg: idealKg, basisKg: basisKg, grams: grams)
    }
}
