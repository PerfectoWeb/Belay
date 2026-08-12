import XCTest

@testable import Vigil

/// The panel's duration format.
///
/// These read the numbers out of the result rather than comparing whole strings.
/// The units are localised, so an assertion on "1h 04m" is really an assertion
/// that the machine running the tests is set to English — and it passed for
/// months for exactly that reason, until the app was switched to Russian and six
/// of them went red at once. What the format actually promises is arithmetic and
/// a two-character minute field, and that is what is checked here.
final class ElapsedTimeTests: XCTestCase {
    private func numbers(_ text: String) -> [String] {
        text.split { !$0.isNumber }.map(String.init)
    }

    func testSecondsBelowAMinute() {
        XCTAssertEqual(numbers(ElapsedTime.compact(0)), ["0"])
        XCTAssertEqual(numbers(ElapsedTime.compact(45)), ["45"])
        XCTAssertEqual(numbers(ElapsedTime.compact(59)), ["59"])
    }

    func testMinutes() {
        XCTAssertEqual(numbers(ElapsedTime.compact(60)), ["1"])
        XCTAssertEqual(numbers(ElapsedTime.compact(719)), ["11"])
    }

    func testHoursPadTheMinuteField() {
        XCTAssertEqual(numbers(ElapsedTime.compact(3600)), ["1", "00"])
        XCTAssertEqual(numbers(ElapsedTime.compact(3840)), ["1", "04"])
    }

    func testDays() {
        XCTAssertEqual(numbers(ElapsedTime.compact(86_400)), ["1", "00"])
    }

    /// A clock stepping backwards (NTP correction, wake from sleep) must not
    /// render "-1s" in the menu bar.
    func testNegativeIntervalsClampToZero() {
        XCTAssertFalse(ElapsedTime.compact(-1).contains("-"))
        XCTAssertEqual(numbers(ElapsedTime.compact(-1)), ["0"])
        XCTAssertEqual(numbers(ElapsedTime.compact(-10_000)), ["0"])
    }

    /// Once hours appear the minute field is always two characters, which is
    /// what stops the row jittering as the number changes width.
    func testWidthIsStableOnceHoursAppear() {
        let widths = Set(
            stride(from: 3600.0, through: 3600.0 + 3540, by: 60).map { ElapsedTime.compact($0).count }
        )
        XCTAssertEqual(widths.count, 1, "elapsed label changes width within the same hour: \(widths)")
    }

    func testSpokenFormIsUsedForVoiceOver() {
        XCTAssertEqual(numbers(ElapsedTime.spoken(0)), ["0"])
        XCTAssertFalse(ElapsedTime.spoken(3900).isEmpty)
        // Both numbers, and no padding zero: the compact form pads the minute
        // field to hold a column still, and read aloud that is "oh four".
        XCTAssertEqual(numbers(ElapsedTime.spoken(3900)), ["1", "5"])
    }
}
