import Foundation

struct ProteinSource: Codable, Identifiable, Hashable {
    var id: String
    var nameHe: String
    var servingText: String
    var servingGrams: Double
    var proteinPerServing: Double
    var proteinPer100g: Double
    var minStage: DietStage
    var note: String
    var sourceURL: URL
}

struct Recipe: Codable, Identifiable, Hashable {
    var id: String
    var nameHe: String
    var ingredients: [String]
    var proteinPerPortion: Double
    var portionText: String
    var minStage: DietStage
    var warnings: [String]
    var sourceURL: URL
}

struct NutritionRule: Codable, Identifiable, Hashable {
    var id: String
    var textHe: String
    var sourceURL: URL
}

struct FoodLibrary: Codable {
    var sources: [ProteinSource]
    var recipes: [Recipe]
    var rules: [NutritionRule]

    static let bundled: FoodLibrary = {
        do {
            guard let url = Bundle.main.url(forResource: "nutrition-library", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            return try load(from: Data(contentsOf: url))
        } catch {
            // FoodLibraryTests guarantees the bundled file is valid; reaching this is a packaging bug.
            assertionFailure("nutrition-library.json failed to load: \(error)")
            return FoodLibrary(sources: [], recipes: [], rules: [])
        }
    }()

    static func load(from data: Data) throws -> FoodLibrary {
        try JSONDecoder().decode(FoodLibrary.self, from: data)
    }

    /// `nil` or `.preSurgery` shows everything (practising before surgery).
    func sources(for stage: DietStage?) -> [ProteinSource] {
        guard let stage, stage != .preSurgery else { return sources }
        return sources.filter { $0.minStage <= stage }
    }

    func recipes(for stage: DietStage?) -> [Recipe] {
        guard let stage, stage != .preSurgery else { return recipes }
        return recipes.filter { $0.minStage <= stage }
    }
}
