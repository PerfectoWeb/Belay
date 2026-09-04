import SwiftUI
import XCTest

@testable import Belay

/// The panel's one ask appears only after Belay has held the Mac through an
/// hour of the user's absence, and never again once either row was answered.
/// The same rule serves both builds: a star in the direct one, a review in the
/// App Store one.
final class PanelStarAskTests: XCTestCase {
    private typealias Card = PanelAskCard<EmptyView>

    func testEligibilityNeedsAnEarnedHourAndNoAnswerYet() {
        XCTAssertFalse(Card.isEligible(awayHeld: 0, settled: false), "nothing earned")
        XCTAssertFalse(Card.isEligible(awayHeld: 59 * 60, settled: false), "under the hour")
        XCTAssertTrue(Card.isEligible(awayHeld: 60 * 60, settled: false))
        XCTAssertTrue(Card.isEligible(awayHeld: 5 * 3600, settled: false))
        XCTAssertFalse(
            Card.isEligible(awayHeld: 5 * 3600, settled: true),
            "either row answered settles both")
    }

    func testTheTwoAsksShareOneAnswer() {
        XCTAssertEqual(StarAsk.key, "belay.starAsk.settled")
    }
}
