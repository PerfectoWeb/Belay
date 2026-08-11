import VigilCore
import XCTest

@testable import Vigil

/// Grouping subagents under the session that spawned them.
///
/// The failure this guards against is a panel that tells the truth about
/// individual rows while lying about the whole: fifty-four agents each holding
/// a top-level slot, the session that started them pushed off the list, and a
/// parent labelled "Idle" while its agents are the reason the Mac is awake.
final class SessionNestingTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    private func row(
        _ id: String,
        parent: String? = nil,
        activity: SessionActivity = .idle,
        kind: String? = nil,
        after seconds: TimeInterval = 0
    ) -> SessionRow {
        SessionRow(
            id: SessionID(id),
            provider: .claudeCode,
            workspace: "f64",
            activity: activity,
            since: start.addingTimeInterval(seconds),
            parent: parent.map(SessionID.init),
            kind: kind)
    }

    func testSubagentsDoNotTakeTopLevelSlots() {
        let nested = SessionRow.nest([
            row("s1"), row("a1", parent: "s1"), row("a2", parent: "s1"), row("s2")
        ])
        XCTAssertEqual(nested.map(\.id.rawValue), ["s1", "s2"])
        XCTAssertEqual(nested[0].children.map(\.id.rawValue), ["a1", "a2"])
        XCTAssertTrue(nested[1].children.isEmpty)
    }

    func testChildrenRunOldestFirst() {
        let nested = SessionRow.nest([
            row("s1"), row("a2", parent: "s1", after: 90), row("a1", parent: "s1", after: 10)
        ])
        XCTAssertEqual(nested[0].children.map(\.id.rawValue), ["a1", "a2"])
    }

    /// A parent can be evicted by TTL while its agents are still running. Losing
    /// the group is acceptable; losing the rows is not — they are holding the
    /// Mac awake.
    func testOrphansStayVisible() {
        let nested = SessionRow.nest([row("a1", parent: "gone", activity: .working)])
        XCTAssertEqual(nested.map(\.id.rawValue), ["a1"])
    }

    /// One level deep on purpose: an agent that spawns agents lands under the
    /// session the user actually started, not under another agent.
    func testGrandchildrenAttachToTheSessionTheUserStarted() {
        let nested = SessionRow.nest([
            row("s1"), row("a1", parent: "s1"), row("a2", parent: "a1")
        ])
        XCTAssertEqual(nested.map(\.id.rawValue), ["s1"])
        XCTAssertEqual(nested[0].children.map(\.id.rawValue), ["a1", "a2"])
    }

    func testACycleDoesNotHangOrDuplicate() {
        let nested = SessionRow.nest([row("a", parent: "b"), row("b", parent: "a")])
        XCTAssertEqual(nested.count + nested.reduce(0) { $0 + $1.children.count }, 2)
    }

    // MARK: - what the row says

    func testAQuietParentReportsItsAgentsWork() {
        let nested = SessionRow.nest([
            row("s1", activity: .idle), row("a1", parent: "s1", activity: .working)
        ])
        XCTAssertEqual(nested[0].activity, .idle, "the session's own state is untouched")
        XCTAssertEqual(nested[0].rollup, .working, "the panel would have claimed Idle mid-run")
    }

    func testWorkOutranksWaiting() {
        let nested = SessionRow.nest([
            row("s1", activity: .awaitingUser),
            row("a1", parent: "s1", activity: .idle),
            row("a2", parent: "s1", activity: .working)
        ])
        XCTAssertEqual(nested[0].rollup, .working)
    }

    func testARowWithNoAgentsReportsItself() {
        XCTAssertEqual(row("s1", activity: .awaitingUser).rollup, .awaitingUser)
    }

    /// The overflow line counts sessions, and the header counts everything, so
    /// "+2 more" can never be measured against a list of fifty-seven.
    func testOverflowIsMeasuredInSessionsNotAgents() {
        let rows =
            (0..<8).map { index in row("s\(index)") }
            + (0..<40).map { index in row("a\(index)", parent: "s0") }
        let nested = SessionRow.nest(rows)
        XCTAssertEqual(nested.count, 8)
        XCTAssertEqual(nested.reduce(0) { $0 + 1 + $1.children.count }, 48)
    }
}
