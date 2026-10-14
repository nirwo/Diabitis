import XCTest
@testable import BariatricHabits

final class DietStageTests: XCTestCase {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        return cal
    }()

    private func day(_ offset: Int, from base: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: base)!
    }

    func test_from_returns_nil_without_surgery_date() {
        XCTAssertNil(DietStage.from(surgeryDate: nil, now: Date(), calendar: calendar))
    }

    func test_from_maps_day_offsets_to_stages() {
        let surgery = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 9))!
        let expectations: [(Int, DietStage)] = [
            (-1, .preSurgery), (0, .liquid), (14, .liquid), (15, .puree),
            (28, .puree), (29, .soft), (56, .soft), (57, .regular), (400, .regular),
        ]
        for (offset, expected) in expectations {
            XCTAssertEqual(DietStage.from(surgeryDate: surgery, now: day(offset, from: surgery), calendar: calendar),
                           expected, "day \(offset)")
        }
    }

    func test_stages_are_ordered() {
        XCTAssertLessThan(DietStage.preSurgery, .liquid)
        XCTAssertLessThan(DietStage.puree, .soft)
        XCTAssertLessThan(DietStage.soft, .regular)
    }
}
