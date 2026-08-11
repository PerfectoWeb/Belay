import Foundation
import XCTest

@testable import Vigil

/// The menu bar mark's frame table. The About pane runs the same frames on a
/// beat of its own, so these guard the frames themselves rather than either
/// schedule.
final class AboutAnimationTests: XCTestCase {
    /// Every frame of the cycle has to be reachable, or the mark twitches
    /// between two of them instead of shimmering.
    func testEveryFrameIsReachable() {
        let cycle = (0..<VigilGlyph.frameCount).map(VigilGlyph.frameDuration).reduce(0, +)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var seen = Set<Int>()
        for step in 0..<400 {
            seen.insert(VigilGlyph.frame(at: start.addingTimeInterval(cycle * Double(step) / 400)))
        }
        XCTAssertEqual(seen.count, VigilGlyph.frameCount, "some frames are never shown")
    }

    /// Most of the menu bar's cycle is the hold. That is what keeps a moving
    /// icon inside the budget docs/08 sets, and it is why the About pane, whose
    /// job is to present rather than to stay out of the way, does not use it.
    func testTheHoldIsMostOfTheCycle() {
        let cycle = (0..<VigilGlyph.frameCount).map(VigilGlyph.frameDuration).reduce(0, +)
        let hold = VigilGlyph.frameDuration(VigilGlyph.frameCount - 1)
        XCTAssertGreaterThan(hold / cycle, 0.5, "the shimmer never rests")
    }

    /// Frames advance monotonically through the cycle and wrap, rather than
    /// jumping about: the mark has to read as one animation.
    func testFramesAdvanceInOrder() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var last = VigilGlyph.frame(at: start)
        var wraps = 0
        for step in 1...200 {
            let frame = VigilGlyph.frame(at: start.addingTimeInterval(Double(step) * 0.05))
            if frame < last {
                wraps += 1
            } else {
                XCTAssertLessThanOrEqual(frame - last, 2, "the mark skipped frames")
            }
            last = frame
        }
        XCTAssertGreaterThan(wraps, 0, "the cycle never came round")
    }
}
