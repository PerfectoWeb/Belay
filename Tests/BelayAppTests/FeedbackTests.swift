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
        for bundle in [Bundle(for: Self.self), Bundle.main] {
            for extension_ in ["wav", "mp3"] {
                if let found = bundle.url(
                    forResource: sound.rawValue, withExtension: extension_)
                {
                    return found
                }
            }
        }
        return nil
    }

    func testEverySoundIsInTheBundle() throws {
        for sound in Feedback.Sound.allCases {
            XCTAssertNotNil(url(sound), "\(sound.rawValue).wav is missing — that moment is silent")
        }
    }

    /// Confirmations, not announcements. A sound long enough to still be playing
    /// when the user has moved on is one they will turn off.
    ///
    /// Some sounds answer to a different clock — they are scored to the
    /// welcome scene's pictures, not to a moment: the spell to the writing it
    /// rings out from, the cinematic to the scene's whole arrival, the typing
    /// bed to the first act. Cutting any to the feedback budget would stop
    /// the sound while its picture is still moving, so each carries the
    /// ceiling of the thing it accompanies. Named exceptions, the way
    /// "thanks" is to the one-note rule; everything else keeps 0.8 s.
    private static let scoredCeilings: [Feedback.Sound: Double] = [
        .welcomeSpell: 8.5,
        .welcomeCinematic: 16.0,
        .welcomeTyping: 7.1,
        .whatsNew: 1.3,
    ]

    func testNothingOutstaysItsWelcome() throws {
        for sound in Feedback.Sound.allCases {
            let file = try XCTUnwrap(url(sound))
            let effect = try XCTUnwrap(NSSound(contentsOf: file, byReference: false))
            let ceiling = Self.scoredCeilings[sound] ?? 0.8
            XCTAssertLessThan(effect.duration, ceiling, "\(sound.rawValue) runs on")
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
