import AppKit
import XCTest

@testable import Belay

/// Which keys open a menu's second half.
final class RevealKeyTests: XCTestCase {
    func testOptionReveals() {
        XCTAssertTrue(RevealKey.held(.option), "Option is what macOS itself uses for alternates")
    }

    func testShiftStillReveals() {
        XCTAssertTrue(
            RevealKey.held(.shift),
            "Shift shipped in 1.6.2 and is written into that version's notes in seven languages")
    }

    func testEitherWithOtherKeysDown() {
        XCTAssertTrue(RevealKey.held([.option, .command]))
        XCTAssertTrue(RevealKey.held([.shift, .control]))
    }

    func testNothingElseReveals() {
        XCTAssertFalse(RevealKey.held([]))
        XCTAssertFalse(RevealKey.held(.command))
        XCTAssertFalse(RevealKey.held([.command, .control]))
    }
}
