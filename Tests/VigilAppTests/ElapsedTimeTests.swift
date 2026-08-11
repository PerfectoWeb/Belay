import XCTest

@testable import Vigil

final class ElapsedTimeTests: XCTestCase {
    func testSecondsBelowAMinute() {
        XCTAssertEqual(ElapsedTime.compact(0), "0s")
        XCTAssertEqual(ElapsedTime.compact(45), "45s")
        XCTAssertEqual(ElapsedTime.compact(59), "59s")
    }

    func testMinutes() {
        XCTAssertEqual(ElapsedTime.compact(60), "1m")
        XCTAssertEqual(ElapsedTime.compact(719), "11m")
    }

    func testHoursPadTheMinuteField() {
        XCTAssertEqual(ElapsedTime.compact(3600), "1h 00m")
        XCTAssertEqual(ElapsedTime.compact(3840), "1h 04m")
    }

    func testDays() {
        XCTAssertEqual(ElapsedTime.compact(86_400), "1d 00h")
    }

    /// A clock stepping backwards (NTP correction, wake from sleep) must not
    /// render "-1s" in the menu bar.
    func testNegativeIntervalsClampToZero() {
        XCTAssertEqual(ElapsedTime.compact(-1), "0s")
        XCTAssertEqual(ElapsedTime.compact(-10_000), "0s")
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
        XCTAssertEqual(ElapsedTime.spoken(0), "0 seconds")
        XCTAssertFalse(ElapsedTime.spoken(3900).isEmpty)
    }
}
