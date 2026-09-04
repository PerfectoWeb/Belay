import BelayCore
import XCTest

@testable import Belay

/// What the panel row is allowed to say beside the name: the tool badge only
/// while the toggle is on and the session is working, the background badge
/// only when no tool call is open, and nothing at all for an idle session.
@MainActor
final class SessionBadgeGateTests: XCTestCase {
    private let since = Date(timeIntervalSince1970: 1_760_000_000)

    private func row(
        activity: SessionActivity, tool: ToolCategory?, background: Bool, badges: Bool
    ) -> SessionRow {
        let state = AppState()
        state.showToolBadges = badges
        var session = SessionState(
            id: SessionID("s1"), provider: .claudeCode, workspace: "acme-api", firstSeen: since)
        session.workingSince = since
        session.activeTool = tool
        session.backgroundSince = background ? since : nil
        state.apply(
            CoordinatorSnapshot(
                state: activity == .working ? .working : .armed, sessions: [session],
                activities: [session.id: activity], holdReason: nil, holdingSince: nil),
            totalAwake: 0)
        return state.sessions[0]
    }

    func testToolBadgeShowsWhileWorkingWithTheToggleOn() {
        let row = row(activity: .working, tool: .command, background: false, badges: true)
        XCTAssertEqual(row.tool, .command)
        XCTAssertFalse(row.background)
    }

    func testToggleOffHidesTheToolBadge() {
        let row = row(activity: .working, tool: .command, background: false, badges: false)
        XCTAssertNil(row.tool)
    }

    func testBackgroundBadgeOnlyWhenNoToolCallIsOpen() {
        let alone = row(activity: .working, tool: nil, background: true, badges: true)
        XCTAssertNil(alone.tool)
        XCTAssertTrue(alone.background)

        let both = row(activity: .working, tool: .search, background: true, badges: true)
        XCTAssertEqual(both.tool, .search)
        XCTAssertFalse(both.background, "an open tool call outranks the background flag")
    }

    func testIdleSessionsWearNoBadges() {
        let row = row(activity: .idle, tool: .command, background: true, badges: true)
        XCTAssertNil(row.tool)
        XCTAssertFalse(row.background)
    }
}
