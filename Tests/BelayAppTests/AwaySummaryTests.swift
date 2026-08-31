import XCTest

@testable import Belay

/// The one banner on return: said once, only when there was something held,
/// and never inflated by slices the user was actually present for.
final class AwaySummaryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testReportsHeldTimeAndFinishesOnReturn() {
        var summary = AwaySummary()
        var now = start

        // Present, holding: nothing accumulates.
        XCTAssertNil(summary.tick(idle: 0, holding: true, now: now))

        // Away for twenty minutes of held work, one finish along the way.
        now += 60
        XCTAssertNil(summary.tick(idle: 6 * 60, holding: true, now: now))
        for _ in 0..<40 {
            now += 30
            XCTAssertNil(summary.tick(idle: 10 * 60, holding: true, now: now))
        }
        summary.noteFinished()

        // Back at the keyboard: one report, then a clean slate.
        now += 30
        let report = summary.tick(idle: 2, holding: true, now: now)
        XCTAssertNotNil(report)
        XCTAssertEqual(report?.finishedRuns, 1)
        XCTAssertEqual(report!.heldAway, 40 * 30, accuracy: 1)
        XCTAssertFalse(summary.isObserving)

        now += 30
        XCTAssertNil(summary.tick(idle: 1, holding: true, now: now), "said once, not twice")
    }

    func testShortHoldsStaySilent() {
        var summary = AwaySummary()
        var now = start
        XCTAssertNil(summary.tick(idle: 6 * 60, holding: true, now: now))
        // Two minutes held is under the floor; the return says nothing.
        for _ in 0..<4 {
            now += 30
            XCTAssertNil(summary.tick(idle: 10 * 60, holding: true, now: now))
        }
        now += 30
        XCTAssertNil(summary.tick(idle: 1, holding: true, now: now))
    }

    func testAwayWithoutHoldingCountsNothing() {
        var summary = AwaySummary()
        var now = start
        XCTAssertNil(summary.tick(idle: 6 * 60, holding: false, now: now))
        for _ in 0..<30 {
            now += 30
            XCTAssertNil(summary.tick(idle: 20 * 60, holding: false, now: now))
        }
        now += 30
        XCTAssertNil(summary.tick(idle: 1, holding: false, now: now), "no hold, no claim")
    }

    func testFinishWhilePresentIsNotRetold() {
        var summary = AwaySummary()
        summary.noteFinished()
        var now = start
        XCTAssertNil(summary.tick(idle: 6 * 60, holding: true, now: now))
        for _ in 0..<12 {
            now += 30
            XCTAssertNil(summary.tick(idle: 10 * 60, holding: true, now: now))
        }
        now += 30
        let report = summary.tick(idle: 1, holding: true, now: now)
        XCTAssertEqual(report?.finishedRuns, 0, "a finish they watched needs no retelling")
    }

    func testPeakThermalIsRemembered() {
        var summary = AwaySummary()
        var now = start
        XCTAssertNil(summary.tick(idle: 6 * 60, holding: true, thermal: 0, now: now))
        for step in 0..<12 {
            now += 30
            XCTAssertNil(
                summary.tick(idle: 10 * 60, holding: true, thermal: step == 5 ? 2 : 0, now: now))
        }
        now += 30
        let report = summary.tick(idle: 1, holding: true, thermal: 0, now: now)
        XCTAssertEqual(report?.peakThermal, 2, "one hot moment is the peak")
    }

    /// The honesty rule: a slice the user was present for part of is dropped,
    /// exactly as the statistics recorder drops it.
    func testPartiallyAttendedSliceIsDropped() {
        var summary = AwaySummary()
        var now = start
        XCTAssertNil(summary.tick(idle: 6 * 60, holding: true, now: now))
        for _ in 0..<20 {
            now += 30
            XCTAssertNil(summary.tick(idle: 10 * 60, holding: true, now: now))
        }
        // A late tick: ten minutes elapsed but they typed six minutes ago —
        // still away now, yet part of the slice was attended. Dropped whole.
        now += 600
        XCTAssertNil(summary.tick(idle: 6 * 60, holding: true, now: now))
        for _ in 0..<20 {
            now += 30
            XCTAssertNil(summary.tick(idle: 10 * 60, holding: true, now: now))
        }
        now += 30
        let report = summary.tick(idle: 1, holding: true, now: now)
        XCTAssertEqual(report!.heldAway, 40 * 30, accuracy: 1, "the touched slice counts nowhere")
    }
}
