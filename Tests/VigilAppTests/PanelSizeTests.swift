import SwiftUI
import VigilCore
import XCTest

@testable import Vigil

/// The panel has to stay a menu bar panel.
///
/// A workflow can spawn fifty-four agents in one session. Before nesting, that
/// was fifty-four top-level rows; the fix is only a fix if expanding them still
/// leaves a popover that fits on a laptop screen.
@MainActor
final class PanelSizeTests: XCTestCase {
    private func rows(sessions: Int, agentsEach: Int) -> [SessionRow] {
        let since = Date(timeIntervalSince1970: 1_760_000_000)
        let flat = (0..<sessions).flatMap { session -> [SessionRow] in
            let parent = SessionID("s\(session)")
            let head = SessionRow(
                id: parent, provider: .claudeCode, workspace: "project-\(session)",
                activity: .working, since: since)
            let children = (0..<agentsEach).map { agent in
                SessionRow(
                    id: SessionID("s\(session)-a\(agent)"), provider: .claudeCode,
                    workspace: "project-\(session)", activity: .working, since: since,
                    parent: parent, kind: "general-purpose")
            }
            return [head] + children
        }
        return SessionRow.nest(flat)
    }

    private func height(_ sessions: [SessionRow]) -> CGFloat {
        let view = NSHostingView(rootView: PanelSessionList(sessions: sessions))
        view.layoutSubtreeIfNeeded()
        return view.fittingSize.height
    }

    func testAHugeWorkflowDoesNotStretchTheList() {
        let small = height(rows(sessions: 1, agentsEach: 2))
        let huge = height(rows(sessions: 1, agentsEach: 54))
        XCTAssertLessThan(
            huge, small + 40,
            "fifty-four agents changed the collapsed list's height — they are not nested")
    }

    func testManySessionsAreCappedUntilAskedFor() {
        let five = height(rows(sessions: 5, agentsEach: 0))
        let fifty = height(rows(sessions: 50, agentsEach: 0))
        XCTAssertLessThan(fifty, five + 40, "the list grew past its visible limit")
    }

    /// The budget that matters: the whole panel, with the list opened as far as
    /// it goes, on the shortest screen Vigil supports. A 13-inch MacBook leaves
    /// about 700 pt under the menu bar.
    func testTheWholePanelFitsAShortScreen() {
        let state = AppState()
        let since = Date(timeIntervalSince1970: 1_760_000_000)
        let sessions = (0..<50).map { index -> SessionState in
            var session = SessionState(
                id: SessionID("s\(index)"), provider: .claudeCode, workspace: "project-\(index)",
                parent: index % 5 == 0 ? nil : SessionID("s0"), kind: "general-purpose",
                firstSeen: since)
            session.workingSince = since
            return session
        }
        state.apply(
            CoordinatorSnapshot(
                state: .working, sessions: sessions,
                activities: sessions.reduce(into: [:]) { $0[$1.id] = .working },
                holdReason: .working(sessions: 50, workspace: "project-0"), holdingSince: since),
            totalAwake: 3600)

        let view = NSHostingView(rootView: PanelView(state: state))
        view.layoutSubtreeIfNeeded()
        let opened = view.fittingSize.height + PanelSessionList.scrollerHeight
        XCTAssertLessThan(opened, 700, "the panel would run off a 13-inch screen when opened")
    }
}
