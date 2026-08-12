import BelaySettings
import XCTest

@testable import Belay

/// The labels on the two Behaviour pop-ups.
///
/// The fallback exists for a value stored by a build whose list differed, and it
/// is `ElapsedTime.compact` — the panel's tight form, with no space before the
/// unit and a padding zero on a round hour. Shipping a preset that lands there
/// puts "1h 00m" in a pop-up, which is what this stops.
final class DurationChoiceTests: XCTestCase {
    func testEveryShippedChoiceHasAWrittenLabel() {
        for seconds in SettingsPresets.gracePeriods {
            XCTAssertTrue(
                DurationChoice.isWritten(seconds),
                "the grace period \(seconds)s falls back to the panel's compact form")
        }
        for limit in SettingsPresets.maxContinuousAwake {
            XCTAssertTrue(
                DurationChoice.isWritten(limit),
                "the maximum \(String(describing: limit)) falls back to the compact form")
        }
    }

    /// A round hour is "1 hour", never "1h 00m", and a unit is never welded to
    /// its number. Both were true of the pop-ups before these labels existed.
    func testLabelsAreWrittenOutRatherThanFormatted() {
        for limit in SettingsPresets.maxContinuousAwake {
            let label = DurationChoice.label(limit)
            XCTAssertFalse(label.contains("00"), "\(label) still has a padding zero")
        }
        for seconds in SettingsPresets.gracePeriods {
            let label = DurationChoice.label(seconds)
            let digits = label.prefix { $0.isNumber }
            XCTAssertFalse(digits.isEmpty, "\(label) starts with no number")
            XCTAssertNotEqual(
                label.dropFirst(digits.count).first, Character("m"),
                "\(label) welds the unit to the number")
        }
    }
}
