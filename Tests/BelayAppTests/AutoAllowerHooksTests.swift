import BelayCore
import XCTest

@testable import Belay

/// Whether a session behind the window can be waiting on a card, read from
/// what the hooks said.
final class AutoAllowerHooksTests: XCTestCase {
    private let moment = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(
        _ name: String, _ provider: ProviderID = .claudeCode, hooked: Bool = true, inTool: Bool = false
    ) -> SessionState {
        var state = SessionState(id: SessionID(name), provider: provider, workspace: "acme", firstSeen: moment)
        if hooked { state.exact = Reading(activity: .idle, at: moment) }
        if inTool { state.openToolCallSince = moment }
        return state
    }

    func testWithoutHooksThereIsNoTelling() {
        XCTAssertTrue(AutoAllower.mayBeAsking([], provider: .claudeCode))
        XCTAssertTrue(AutoAllower.mayBeAsking([session("a", hooked: false)], provider: .claudeCode))
    }

    func testHookedSessionsOutsideAToolCallCannotBeAsking() {
        let sessions = [session("a"), session("b")]
        XCTAssertFalse(AutoAllower.mayBeAsking(sessions, provider: .claudeCode))
    }

    func testAnOpenToolCallAnywhereMayBeAsking() {
        let sessions = [session("a"), session("b", inTool: true)]
        XCTAssertTrue(AutoAllower.mayBeAsking(sessions, provider: .claudeCode))
    }

    func testAnotherAgentsToolCallDoesNotCount() {
        let sessions = [session("a"), session("c", .codex, inTool: true)]
        XCTAssertFalse(AutoAllower.mayBeAsking(sessions, provider: .claudeCode))
    }
}
