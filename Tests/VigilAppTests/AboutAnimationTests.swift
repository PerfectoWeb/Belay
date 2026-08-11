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

    /// Down, not up. The direction was reversed on purpose and the wobble that
    /// makes the field look alive is well under the drift, so no star ever
    /// creeps backwards between frames.
    func testStarsFall() {
        for index in stride(from: 0, to: 90, by: 7) {
            var last = Starfield.Star(index: index, at: 0).down
            for step in 1...300 {
                let down = Starfield.Star(index: index, at: Double(step) * 0.05).down
                let wrapped = down < last - 0.5
                XCTAssertTrue(
                    wrapped || down >= last, "star \(index) moved up at step \(step)")
                last = down
            }
        }
    }

    /// A comet is worth watching because the sky is usually empty. If the slots
    /// ever overlap into a steady stream this fails, which is the point.
    func testTheSkyIsUsuallyEmpty() {
        let size = CGSize(width: 480, height: 240)
        var lit = 0
        var seen = 0
        for step in 0..<2000 {
            let now = Double(step) * 0.05
            let comets = (0..<Starfield.cometSlots).compactMap {
                Starfield.Comet(slot: $0, at: now, in: size)
            }
            if !comets.isEmpty {
                lit += 1
                seen = max(seen, comets.count)
            }
        }
        XCTAssertGreaterThan(seen, 0, "no comet ever appeared")
        XCTAssertLessThan(
            Double(lit) / 2000, 0.55, "there is nearly always a comet on screen")
    }

    /// It has to arrive and burn out. Switching one on at full brightness and
    /// off again is the thing this replaced.
    func testACometBurnsOutRatherThanSwitchingOff() {
        let size = CGSize(width: 480, height: 240)
        var samples: [Double] = []
        for step in 0..<400 {
            guard let comet = Starfield.Comet(slot: 0, at: Double(step) * 0.01, in: size) else {
                continue
            }
            samples.append(comet.alpha)
        }
        let first = try? XCTUnwrap(samples.first)
        let last = try? XCTUnwrap(samples.last)
        XCTAssertLessThan(first ?? 1, 0.1, "the comet appeared at full brightness")
        XCTAssertLessThan(last ?? 1, 0.1, "the comet was switched off rather than fading")
        XCTAssertGreaterThan(samples.max() ?? 0, 0.5, "the comet never got bright")
    }
}
