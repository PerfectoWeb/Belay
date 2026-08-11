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
        workspace: String = "f64",
        name: String? = nil,
        after seconds: TimeInterval = 0
    ) -> SessionRow {
        SessionRow(
            id: SessionID(id),
            provider: .claudeCode,
            workspace: workspace,
            activity: activity,
            since: start.addingTimeInterval(seconds),
            parent: parent.map(SessionID.init),
            kind: kind,
            name: name)
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

/// Telling two sessions in one checkout apart.
///
/// The panel showed two rows both titled "Vigil", one Working and one Idle, with
/// nothing on screen saying which was which. They are separate sessions, not a
/// parent and a child, so nesting them would misdescribe the structure — the row
/// carries the agent's own name for the session instead, and only when the
/// workspace alone would be ambiguous.
final class SessionDisambiguationTests: XCTestCase {
    private func row(_ id: String, workspace: String, name: String?) -> SessionRow {
        SessionRow(
            id: SessionID(id),
            provider: .claudeCode,
            workspace: workspace,
            activity: .idle,
            since: Date(timeIntervalSince1970: 1_760_000_000),
            name: name)
    }

    func testASingleSessionIsPlain() {
        let rows = SessionRow.disambiguate([row("s1", workspace: "Vigil", name: "vigil-9a")])
        XCTAssertNil(rows[0].detail)
        XCTAssertEqual(rows[0].title, "Vigil", "a lone session grew a suffix nobody needs")
    }

    func testTwoSessionsInOneWorkspaceBothGetASuffix() {
        let rows = SessionRow.disambiguate([
            row("s1", workspace: "Vigil", name: "vigil-9a"),
            row("s2", workspace: "Vigil", name: "vigil-74")
        ])
        XCTAssertEqual(rows.map(\.detail), ["9a", "74"])
        XCTAssertEqual(rows.map(\.title), ["Vigil · 9a", "Vigil · 74"])
    }

    func testSessionsInDifferentWorkspacesStayPlain() {
        let rows = SessionRow.disambiguate([
            row("s1", workspace: "Vigil", name: "vigil-9a"),
            row("s2", workspace: "Ledger", name: "ledger-31")
        ])
        XCTAssertEqual(rows.compactMap(\.detail), [])
        XCTAssertEqual(rows.map(\.title), ["Vigil", "Ledger"])
    }

    /// Only the colliding workspace is touched. A third project sharing the
    /// panel must not pick up a suffix because two other rows collided.
    func testOnlyTheAmbiguousWorkspaceIsMarked() {
        let rows = SessionRow.disambiguate([
            row("s1", workspace: "Vigil", name: "vigil-9a"),
            row("s2", workspace: "Vigil", name: "vigil-74"),
            row("s3", workspace: "Ledger", name: "ledger-31")
        ])
        XCTAssertEqual(rows.map(\.detail), ["9a", "74", nil])
    }

    /// Tier C fills the name in a sweep or two after the row first appears, and
    /// a row with no name yet must still show something rather than nothing.
    func testARowWithNoNameFallsBackToTheWorkspace() {
        let rows = SessionRow.disambiguate([
            row("s1", workspace: "Vigil", name: nil),
            row("s2", workspace: "Vigil", name: "vigil-74")
        ])
        XCTAssertEqual(rows.map(\.title), ["Vigil", "Vigil · 74"])
    }

    /// The name is derived from the folder, so repeating its first half beside
    /// the workspace it came from would add width and no information.
    func testTheSuffixDropsTheWorkspacePartOfTheName() {
        let rows = SessionRow.disambiguate([
            row("s1", workspace: "my-project", name: "my-project-9a"),
            row("s2", workspace: "my-project", name: "solo")
        ])
        XCTAssertEqual(rows.map(\.detail), ["9a", "solo"])
    }
}
