import XCTest

@testable import Belay

/// The dirty-shutdown breadcrumb: a SIGKILL writes nothing, so the next
/// launch has to read the absence. Born from a field report — Belay gone in
/// the morning, no crash report, log simply stopping mid-hold.
@MainActor
final class DiagnosticsTests: XCTestCase {
    func testAGoodbyeAfterTheLastHelloIsClean() {
        let tail = """
            2026-08-25T10:00:00Z  collection on, Belay 1.6.0
            2026-08-25T12:00:00Z  hold on reason="x" display=1
            2026-08-25T12:34:00Z  collection off
            """
        XCTAssertFalse(Diagnostics.endedDirty(tail: tail))
    }

    func testAHelloWithNoGoodbyeIsDirty() {
        let tail = """
            2026-08-25T10:00:00Z  collection off
            2026-08-25T11:00:00Z  collection on, Belay 1.6.0
            2026-08-25T12:00:00Z  hold on reason="x" display=1
            """
        XCTAssertTrue(Diagnostics.endedDirty(tail: tail))
    }

    func testALogWithNoMarkersSaysNothing() {
        XCTAssertFalse(Diagnostics.endedDirty(tail: ""))
        XCTAssertFalse(Diagnostics.endedDirty(tail: "2026-08-25T10:00:00Z  hold on"))
    }

    func testOnlyTheLatestSessionCounts() {
        let tail = """
            2026-08-24T10:00:00Z  collection on, Belay 1.5.0
            2026-08-24T22:00:00Z  collection off
            2026-08-25T09:00:00Z  collection on, Belay 1.6.0
            """
        XCTAssertTrue(Diagnostics.endedDirty(tail: tail))
    }
}

/// The other way a log can hurt: not one enormous line, but the same short one
/// forever. An unreachable lid helper wrote its failure every fifteen seconds —
/// 5 760 identical lines a day, none of them saying anything the first had not.
@MainActor
final class DiagnosticsRepeatTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        // The counter is shared, so each test starts from a line of its own.
        _ = Diagnostics.collapse("reset \(UUID().uuidString)", now: start)
    }

    func testTheFirstLineIsWrittenAtOnce() {
        XCTAssertEqual(Diagnostics.collapse("lid xpc error", now: start), ["lid xpc error"])
    }

    func testRepeatsAreCountedRatherThanWritten() {
        _ = Diagnostics.collapse("lid xpc error", now: start)
        for tick in 1...5 {
            let at = start.addingTimeInterval(Double(tick))
            XCTAssertEqual(
                Diagnostics.collapse("lid xpc error", now: at), [],
                "repeat \(tick) should be counted, not written")
        }
    }

    func testADifferentLineFlushesTheCount() {
        _ = Diagnostics.collapse("lid xpc error", now: start)
        for tick in 1...3 {
            _ = Diagnostics.collapse("lid xpc error", now: start.addingTimeInterval(Double(tick)))
        }
        XCTAssertEqual(
            Diagnostics.collapse("hold on", now: start.addingTimeInterval(10)),
            ["the line above repeated 3 more times", "hold on"])
    }

    /// A line that arrives in a flood costs one summary carrying the whole
    /// count, rather than a line each or a number nobody can see.
    func testAFloodCostsOneLineCarryingTheCount() {
        _ = Diagnostics.collapse("lid xpc error", now: start)
        var written: [String] = []
        // A hundred a second for exactly one interval's worth of time.
        let ticks = Int(Diagnostics.firstWindow) * 100
        for tick in 1...ticks {
            written += Diagnostics.collapse(
                "lid xpc error", now: start.addingTimeInterval(Double(tick) / 100))
        }
        XCTAssertEqual(written.count, 1, "one summary, not six thousand lines")
        XCTAssertEqual(written.first, "the line above repeated \(ticks) more times")
    }

    func testTheIntervalAlsoForcesASummary() {
        _ = Diagnostics.collapse("lid xpc error", now: start)
        _ = Diagnostics.collapse("lid xpc error", now: start.addingTimeInterval(15))
        let late = start.addingTimeInterval(Diagnostics.firstWindow + 1)
        XCTAssertEqual(
            Diagnostics.collapse("lid xpc error", now: late),
            ["the line above repeated 2 more times"])
    }

    /// The interval widens, so a fault in its tenth hour costs one line rather
    /// than the same handful it cost in its first minute.
    func testSummariesGrowFurtherApart() {
        _ = Diagnostics.collapse("stuck", now: start)
        var gaps: [TimeInterval] = []
        var last = start
        var at = start
        for tick in 1...2400 {
            at = start.addingTimeInterval(Double(tick) * 15)
            if !Diagnostics.collapse("stuck", now: at).isEmpty {
                gaps.append(at.timeIntervalSince(last))
                last = at
            }
        }
        XCTAssertGreaterThan(gaps.count, 3, "the fault keeps being reported")
        XCTAssertGreaterThan(gaps.last!, gaps.first!, "and less and less often")
        XCTAssertLessThanOrEqual(
            gaps.last!, Diagnostics.longestWindow + 30, "but never stops entirely")
    }

    /// 5 760 lines a day becomes a few dozen, which is the whole point.
    func testADayOfFifteenSecondFailuresIsNotADayOfLines() {
        _ = Diagnostics.collapse("lid xpc error", now: start)
        var lines = 1
        for tick in 1...5760 {
            lines += Diagnostics.collapse(
                "lid xpc error", now: start.addingTimeInterval(Double(tick) * 15)).count
        }
        XCTAssertLessThan(lines, 40, "a day of one repeating fault should not fill the log")
        XCTAssertGreaterThan(lines, 1, "but it must not disappear from it either")
    }
}
