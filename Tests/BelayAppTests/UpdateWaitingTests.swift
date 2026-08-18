import XCTest

@testable import Belay

/// The mark in the corner of the status item is the only unprompted thing Belay
/// says about updates, so what turns it on is worth pinning down.
final class UpdateWaitingTests: XCTestCase {
    private var available: ReleaseChecker.Status {
        .available(version: "1.2.1", url: URL(string: "https://example.com/Belay.dmg")!)
    }

    func testOnlyAPublishedUpdateCountsAsWaiting() {
        XCTAssertTrue(UpdateWaiting.isWaiting(available))
    }

    func testEveryOtherAnswerIsSilent() {
        XCTAssertFalse(UpdateWaiting.isWaiting(.upToDate(Date())))
        XCTAssertFalse(UpdateWaiting.isWaiting(.never))
        XCTAssertFalse(UpdateWaiting.isWaiting(.checking))
        XCTAssertFalse(UpdateWaiting.isWaiting(.noneYet))
        XCTAssertFalse(UpdateWaiting.isWaiting(.failed("offline")))
    }
}
