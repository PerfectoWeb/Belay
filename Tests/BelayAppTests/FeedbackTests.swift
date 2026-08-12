import AppKit
import BelayCore
import XCTest

@testable import Belay

/// The sounds.
///
/// Every way these can break is silent. A file that did not make it into the
/// bundle, a case renamed without renaming the file, two modes sharing a note:
/// the app carries on and simply says nothing, which is indistinguishable from
/// somebody having turned the sounds off.
@MainActor
final class FeedbackTests: XCTestCase {
    private func url(_ sound: Feedback.Sound) -> URL? {
        Bundle(for: Self.self).url(forResource: sound.rawValue, withExtension: "wav")
            ?? Bundle.main.url(forResource: sound.rawValue, withExtension: "wav")
    }

    func testEverySoundIsInTheBundle() throws {
        for sound in Feedback.Sound.allCases {
            XCTAssertNotNil(url(sound), "\(sound.rawValue).wav is missing — that moment is silent")
        }
    }

    /// Confirmations, not announcements. A sound long enough to still be playing
    /// when the user has moved on is one they will turn off.
    func testNothingOutstaysItsWelcome() throws {
        for sound in Feedback.Sound.allCases {
            let file = try XCTUnwrap(url(sound))
            let effect = try XCTUnwrap(NSSound(contentsOf: file, byReference: false))
            XCTAssertLessThan(effect.duration, 0.8, "\(sound.rawValue) runs on")
            XCTAssertGreaterThan(effect.duration, 0.05, "\(sound.rawValue) is a click")
        }
    }

    /// The point of three notes is telling the three modes apart without
    /// looking. Two modes sharing one is worse than no sound at all, because it
    /// says the wrong thing rather than nothing.
    func testEachModeHasItsOwnNote() {
        let notes = AwakeMode.allCases.map(Feedback.sound(for:))
        XCTAssertEqual(Set(notes).count, AwakeMode.allCases.count, "two modes sound the same")
    }
}
