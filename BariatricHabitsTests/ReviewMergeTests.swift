import XCTest
@testable import BariatricHabits

/// The review screen holds a copy of the meal; analysis may land while it is open.
final class ReviewMergeTests: XCTestCase {
    private let egg = FoodItem(name: "ביצה", grams: 50, proteinG: 6.3, confidence: .high)
    private let chicken = FoodItem(name: "עוף", grams: 80, proteinG: 24)

    private func opened() -> FoodEntry {
        FoodEntry(date: Date(), photoFileName: "a.jpg", status: .analyzing, cookingNote: "בתנור")
    }

    private func analyzed(from copy: FoodEntry) -> FoodEntry {
        var live = copy
        live.items = [egg]
        live.notes = "נראה טעים"
        live.advice = ["להתחיל מהחלבון"]
        live.analyzedCookingNote = "בתנור"
        live.status = .needsReview
        return live
    }

    func test_result_arrives_while_review_open_then_save_keeps_items_and_advice() {
        let copy = opened()
        let merged = copy.merging(liveAnalysisFrom: analyzed(from: copy))
        XCTAssertEqual(merged.items, [egg])
        XCTAssertEqual(merged.advice, ["להתחיל מהחלבון"])
        XCTAssertEqual(merged.notes, "נראה טעים")
        XCTAssertEqual(merged.analyzedCookingNote, "בתנור")
    }

    func test_user_edited_items_win_over_arrived_items() {
        var copy = opened()
        copy.items = [chicken]
        let merged = copy.merging(liveAnalysisFrom: analyzed(from: opened()))
        XCTAssertEqual(merged.items, [chicken])
        XCTAssertEqual(merged.advice, ["להתחיל מהחלבון"], "tips are still kept")
    }

    func test_merge_keeps_local_analysis_fields_when_present() {
        var copy = analyzed(from: opened())
        copy.advice = ["טיפ ישן"]
        copy.notes = "הערה"
        var live = copy
        live.advice = ["טיפ חדש"]
        live.notes = "אחרת"
        let merged = copy.merging(liveAnalysisFrom: live)
        XCTAssertEqual(merged.advice, ["טיפ ישן"])
        XCTAssertEqual(merged.notes, "הערה")
    }

    func test_untouched_form_adopts_arrived_analysis() throws {
        let copy = opened()
        let adopted = try XCTUnwrap(copy.adoptingAnalysis(from: analyzed(from: copy), isEdited: false))
        XCTAssertEqual(adopted.items, [egg])
        XCTAssertEqual(adopted.status, .needsReview)
        XCTAssertEqual(adopted.advice, ["להתחיל מהחלבון"])
        XCTAssertEqual(adopted.notes, "נראה טעים")
        XCTAssertEqual(adopted.analyzedCookingNote, "בתנור")
    }

    func test_edited_form_does_not_adopt() {
        let copy = opened()
        XCTAssertNil(copy.adoptingAnalysis(from: analyzed(from: copy), isEdited: true))
    }

    func test_adopts_only_when_live_reaches_needsReview_from_waiting() {
        let copy = opened()
        var stillAnalyzing = copy
        stillAnalyzing.status = .analyzing
        XCTAssertNil(copy.adoptingAnalysis(from: stillAnalyzing, isEdited: false))
        let reviewed = analyzed(from: copy)
        XCTAssertNil(reviewed.adoptingAnalysis(from: reviewed, isEdited: false), "copy already has the analysis")
    }
}
