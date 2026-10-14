import XCTest
@testable import BariatricHabits

final class CookingNoteTests: XCTestCase {
    func test_chips_and_text_join_in_display_order() {
        var draft = CookingNoteDraft(note: nil)
        draft.toggle("מטוגן בשמן")
        draft.toggle("מבושל")
        draft.text = "  בכף שמן זית "
        XCTAssertEqual(draft.note, "מבושל, מטוגן בשמן, בכף שמן זית")
    }

    func test_toggle_twice_removes_chip() {
        var draft = CookingNoteDraft(note: nil)
        draft.toggle("מאודה")
        draft.toggle("מאודה")
        XCTAssertFalse(draft.isSelected("מאודה"))
        XCTAssertNil(draft.note)
    }

    func test_empty_draft_is_nil() {
        var draft = CookingNoteDraft(note: nil)
        draft.text = "   \n "
        XCTAssertNil(draft.note)
    }

    func test_note_is_capped_at_200_chars() {
        var draft = CookingNoteDraft(note: nil)
        draft.text = String(repeating: "א", count: 250)
        XCTAssertEqual(draft.note?.count, 200)
    }

    func test_existing_note_parses_back_into_chips_and_text() {
        let draft = CookingNoteDraft(note: "מטוגן בשמן, בכף שמן זית, עם רוטב עגבניות")
        XCTAssertTrue(draft.isSelected("מטוגן בשמן"))
        XCTAssertFalse(draft.isSelected("מבושל"))
        XCTAssertEqual(draft.text, "בכף שמן זית, עם רוטב עגבניות")
        XCTAssertEqual(draft.note, "מטוגן בשמן, בכף שמן זית, עם רוטב עגבניות")
    }

    func test_partial_chip_match_stays_text() {
        let draft = CookingNoteDraft(note: "מטוגן בשמן קנולה")
        XCTAssertFalse(draft.isSelected("מטוגן בשמן"))
        XCTAssertEqual(draft.text, "מטוגן בשמן קנולה")
    }

    func test_options_are_the_approved_copy() {
        XCTAssertEqual(CookingNoteDraft.options,
                       ["מבושל", "אפוי בתנור", "מטוגן בשמן", "צלוי/גריל", "מאודה", "טרי/לא מבושל"])
    }
}
