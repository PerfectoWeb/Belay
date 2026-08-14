import AppKit
import Foundation
import XCTest

@testable import Belay

/// The welcome scene's two ramps.
///
/// `OnboardingScene.working` and `OnboardingScene.asleep` are the whole of the
/// animation's behaviour: everything drawn — the slack in the rope, the light
/// in the screen, whether the plug is in its socket — is one of these two
/// numbers wearing a different coat. They are static and internal so this file
/// can walk them, which the source has invited since it was written and nothing
/// ever did.
final class OnboardingSceneTests: XCTestCase {
    private let loop = OnboardingScene.loop
    /// A third of a frame at 30fps, which is finer than anything that has to be
    /// resolved and coarse enough to run instantly.
    private let step = 1.0 / 90

    private func walk(_ ramp: (Double) -> Double) -> [(time: Double, value: Double)] {
        stride(from: 0, through: loop, by: step).map { ($0, ramp($0)) }
    }

    /// The loop repeats, so its last frame has to be its first one. This is the
    /// bug the nine-second length exists to avoid: an earlier version wrapped
    /// from a full belly of slack to a dead straight rope in a single frame, on
    /// the first animation anybody ever sees.
    func testBothRampsArriveBackWhereTheyStarted() {
        XCTAssertEqual(OnboardingScene.working(at: 0), OnboardingScene.working(at: loop), accuracy: 0.01)
        XCTAssertEqual(OnboardingScene.asleep(at: 0), OnboardingScene.asleep(at: loop), accuracy: 0.01)
    }

    /// Both are read as opacities and as fractions of a distance. Outside nought
    /// to one they do not fail, they draw: a negative one puts the plug above
    /// where the rope can reach.
    func testNeitherRampLeavesItsRange() {
        for (time, value) in walk(OnboardingScene.working) {
            XCTAssertTrue((0...1).contains(value), "working is \(value) at \(time)")
        }
        for (time, value) in walk(OnboardingScene.asleep) {
            XCTAssertTrue((0...1).contains(value), "asleep is \(value) at \(time)")
        }
    }

    /// No step in either ramp may be big enough to see as a jump. At 30fps a
    /// frame is three of these steps, so a limit of a twentieth here is a
    /// fifteenth of the range in a frame — under what reads as movement rather
    /// than as a cut.
    func testNeitherRampJumps() {
        for ramp in [OnboardingScene.working, OnboardingScene.asleep] {
            let walked = walk(ramp)
            for (previous, next) in zip(walked, walked.dropFirst()) {
                XCTAssertLessThan(
                    abs(next.value - previous.value), 0.05,
                    "jump at \(next.time)")
            }
        }
    }

    /// The grace period, which is the reason this app exists and the part the
    /// picture is there to show: a stretch where the agent has stopped and the
    /// Mac is still being held awake. It was six tenths of a second once, and
    /// at that length it passed for a rendering delay.
    func testTheGracePeriodIsLongEnoughToRead() {
        let quiet = stride(from: 0, through: loop, by: step)
            .filter { OnboardingScene.working(at: $0) == 0 && OnboardingScene.asleep(at: $0) == 0 }
        let span = (quiet.max() ?? 0) - (quiet.min() ?? 0)
        XCTAssertGreaterThan(span, 1.4, "the pause between stopping and sleeping is too short to see")
    }

    /// The Mac may never *start* falling asleep while the agent is working.
    /// Getting this wrong draws Belay letting go mid-run, which is the one
    /// thing it promises not to do, and nothing in the ramps enforces it: they
    /// are two independent piecewise functions that happen to be written next
    /// to each other.
    ///
    /// Not "asleep is zero whenever working is high", which is what this
    /// checked first and is a different and wrong claim. The two overlap once a
    /// loop by design: the next run starts at 8.1 and the Mac is still coming
    /// back up, so for a few tenths the agent is working *and* the screen is
    /// part-dark. That is what waking up looks like. What must not happen is
    /// the number going the other way.
    func testTheMacNeverStartsSleepingWhileTheAgentWorks() {
        for time in stride(from: 0, through: loop - step, by: step)
        where OnboardingScene.working(at: time) > 0.01 {
            let now = OnboardingScene.asleep(at: time)
            let next = OnboardingScene.asleep(at: time + step)
            XCTAssertLessThanOrEqual(
                next, now + 0.0001,
                "the Mac starts going to sleep at \(time) while the agent is still working")
        }
    }

    /// Sleep has to follow the work stopping, never lead it.
    func testSleepStartsAfterTheWorkStops() {
        let stopped = stride(from: 0, through: loop, by: step)
            .first { OnboardingScene.working(at: $0) == 0 } ?? loop
        let sleeping = stride(from: 0, through: loop, by: step)
            .first { OnboardingScene.asleep(at: $0) > 0 } ?? loop
        XCTAssertGreaterThan(sleeping, stopped, "the Mac starts sleeping before the agent stops")
    }

    /// Nothing is ever heard over anything else, including across the wrap.
    ///
    /// The scene's sounds are scheduled by a list of times and played by files
    /// of a fixed length, so two of them landing on top of each other is
    /// arithmetic and not something anybody should have to notice by ear.
    func testNoTwoSceneSoundsAreHeardAtOnce() throws {
        let cues = OnboardingScene.cues
        var last: (at: Double, ends: Double)?
        for cue in cues {
            let file = try XCTUnwrap(
                Bundle(for: Self.self).url(forResource: cue.sound.rawValue, withExtension: "wav")
                    ?? Bundle.main.url(forResource: cue.sound.rawValue, withExtension: "wav"))
            let effect = try XCTUnwrap(NSSound(contentsOf: file, byReference: false))
            if let previous = last {
                XCTAssertLessThanOrEqual(
                    previous.ends, cue.at,
                    "\(cue.sound.rawValue) at \(cue.at) starts before the one before it ends")
            }
            last = (cue.at, cue.at + effect.duration)
        }
        // And the last one has to be finished before the loop comes round and
        // the first one starts again.
        let wrap = try XCTUnwrap(last)
        XCTAssertLessThanOrEqual(
            wrap.ends, loop + (cues.first?.at ?? 0), "the last sound runs into the next pass")
    }
}
