import XCTest
@testable import BariatricHabits

final class FoodItemEditingTests: XCTestCase {
    func test_changing_grams_scales_protein_proportionally() {
        let package = FoodItem(name: "קוטג'", grams: 250, proteinG: 27.5)
        let half = package.withGrams(125)
        XCTAssertEqual(half.grams, 125)
        XCTAssertEqual(half.proteinG, 13.75, accuracy: 0.001)
    }

    func test_changing_grams_from_zero_keeps_protein() {
        let item = FoodItem(name: "x", grams: 0, proteinG: 8)
        XCTAssertEqual(item.withGrams(50).proteinG, 8)
    }

    func test_parseDecimal_accepts_dot_and_comma() {
        XCTAssertEqual(parseDecimal("50"), 50)
        XCTAssertEqual(parseDecimal(" 12.5 "), 12.5)
        XCTAssertEqual(parseDecimal("12,5"), 12.5)
    }

    func test_parseDecimal_rejects_empty_and_text() {
        XCTAssertNil(parseDecimal(""))
        XCTAssertNil(parseDecimal("abc"))
        XCTAssertNil(parseDecimal("-3"))
    }
}
