import XCTest
@testable import BariatricHabits

final class FoodLibraryTests: XCTestCase {
    private var library: FoodLibrary!

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "nutrition-library", withExtension: "json"))
        library = try FoodLibrary.load(from: Data(contentsOf: url))
    }

    func test_bundled_library_has_all_verified_items() {
        XCTAssertEqual(library.sources.count, 26)
        XCTAssertEqual(library.recipes.count, 7)
        XCTAssertEqual(library.rules.count, 9)
    }

    func test_ids_are_unique() {
        let ids = library.sources.map(\.id) + library.recipes.map(\.id) + library.rules.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func test_serving_protein_matches_per_100g() {
        for source in library.sources {
            let expected = source.proteinPer100g * source.servingGrams / 100
            XCTAssertEqual(source.proteinPerServing, expected, accuracy: 0.1, source.id)
        }
    }

    func test_every_item_cites_an_https_source() {
        let urls = library.sources.map(\.sourceURL) + library.recipes.map(\.sourceURL) + library.rules.map(\.sourceURL)
        for url in urls { XCTAssertEqual(url.scheme, "https", url.absoluteString) }
    }

    func test_stage_filtering() {
        XCTAssertEqual(library.sources(for: nil).count, 26)
        XCTAssertEqual(library.sources(for: .preSurgery).count, 26)
        XCTAssertEqual(library.sources(for: .liquid).map(\.id), ["skim-milk"])
        let puree = Set(library.sources(for: .puree).map(\.id))
        XCTAssertTrue(puree.contains("cottage-5"))
        XCTAssertFalse(puree.contains("beef-95"))
        XCTAssertFalse(puree.contains("egg-boiled"))
        XCTAssertFalse(library.recipes(for: .soft).contains { $0.minStage == .regular })
    }

    func test_bundled_static_loads() {
        XCTAssertEqual(FoodLibrary.bundled.sources.count, 26)
    }
}
