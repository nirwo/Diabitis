import XCTest
@testable import BariatricHabits

final class FoodItemEditingTests: XCTestCase {
    private let package = FoodItem(name: "קוטג'", grams: 250, proteinG: 27.5)

    func test_changing_grams_scales_protein_proportionally() {
        var edit = FoodAmountEdit(item: package)
        XCTAssertTrue(edit.setGrams("125"))
        XCTAssertEqual(edit.grams, 125)
        XCTAssertEqual(edit.proteinG, 13.75, accuracy: 0.001)
    }

    func test_typing_through_zero_grams_keeps_protein_per_gram() {
        var edit = FoodAmountEdit(item: package)
        edit.setGrams("00")
        XCTAssertEqual(edit.proteinG, 0)
        edit.setGrams("100")
        XCTAssertEqual(edit.proteinG, 11, accuracy: 0.001)
    }

    func test_edited_protein_sets_the_new_ratio() {
        var edit = FoodAmountEdit(item: package)
        edit.setProtein("20")
        edit.setGrams("125")
        XCTAssertEqual(edit.proteinG, 10, accuracy: 0.001)
    }

    func test_item_without_grams_keeps_protein_until_ratio_is_known() {
        var edit = FoodAmountEdit(item: FoodItem(name: "x", grams: 0, proteinG: 8))
        edit.setGrams("50")
        XCTAssertEqual(edit.proteinG, 8)
        edit.setProtein("8")
        edit.setGrams("100")
        XCTAssertEqual(edit.proteinG, 16, accuracy: 0.001)
    }

    func test_non_numeric_text_changes_nothing() {
        var edit = FoodAmountEdit(item: package)
        XCTAssertFalse(edit.setGrams(""))
        XCTAssertFalse(edit.setProtein("abc"))
        XCTAssertEqual(edit.grams, 250)
        XCTAssertEqual(edit.proteinG, 27.5)
    }

    func test_parseDecimal_accepts_dot_and_comma() {
        XCTAssertEqual(parseDecimal("50"), 50)
        XCTAssertEqual(parseDecimal(" 12.5 "), 12.5)
        XCTAssertEqual(parseDecimal("12,5"), 12.5)
        XCTAssertEqual(parseDecimal("1."), 1)
        XCTAssertEqual(parseDecimal(".5"), 0.5)
    }

    func test_parseDecimal_rejects_empty_text_negative_and_non_finite() {
        XCTAssertNil(parseDecimal(""))
        XCTAssertNil(parseDecimal("abc"))
        XCTAssertNil(parseDecimal("-3"))
        XCTAssertNil(parseDecimal("nan"))
        XCTAssertNil(parseDecimal("inf"))
    }
}
