import BelayCore
import XCTest

@testable import Belay

/// The recent list must remember real runs, skip blips and subagents, and
/// let its tail fall off the cap.
final class SessionHistoryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot(_ sessions: [SessionState]) -> CoordinatorSnapshot {
        var snapshot = CoordinatorSnapshot.idle
        snapshot.sessions = sessions
        return snapshot
    }

    private func session(
        _ id: String, workspace: String? = "belay", parent: String? = nil, seen: Date
    ) -> SessionState {
        SessionState(
            id: SessionID(id), provider: .claudeCode, workspace: workspace,
            parent: parent.map(SessionID.init), firstSeen: seen)
    }

    func testAFinishedSessionBecomesARecord() {
        var tracker = SessionHistoryTracker()
        XCTAssertEqual(tracker.diff(snapshot([session("a", seen: start)]), now: start), [])

        let ended = tracker.diff(snapshot([]), now: start + 600)
        XCTAssertEqual(ended.count, 1)
        XCTAssertEqual(ended[0].workspace, "belay")
        XCTAssertEqual(ended[0].duration, 600, accuracy: 1)
    }

    func testBlipsAndSubagentsStayOut() {
        var tracker = SessionHistoryTracker()
        _ = tracker.diff(
            snapshot([
                session("short", seen: start),
                session("child", parent: "short", seen: start),
            ]), now: start)
        // Gone after thirty seconds: a blip, and its subagent was never
        // tracked at all.
        let ended = tracker.diff(snapshot([]), now: start + 30)
        XCTAssertEqual(ended, [])
    }

    func testALateWorkspaceNameIsKept() {
        var tracker = SessionHistoryTracker()
        _ = tracker.diff(snapshot([session("a", workspace: nil, seen: start)]), now: start)
        _ = tracker.diff(snapshot([session("a", workspace: "myna", seen: start)]), now: start + 60)
        let ended = tracker.diff(snapshot([]), now: start + 600)
        XCTAssertEqual(ended.first?.workspace, "myna")
    }

    @MainActor
    func testTheStoreCapsAtCapacity() {
        let suite = "belay.tests.session-history"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SessionHistoryStore(defaults: defaults)
        for index in 0..<(SessionHistoryStore.capacity + 5) {
            store.append([
                SessionRecord(
                    id: UUID(), provider: .codex, workspace: "w\(index)",
                    startedAt: start, endedAt: start + TimeInterval(index))
            ])
        }
        let kept = store.load()
        XCTAssertEqual(kept.count, SessionHistoryStore.capacity)
        XCTAssertEqual(kept.first?.workspace, "w\(SessionHistoryStore.capacity + 4)", "newest first")

        store.reset()
        XCTAssertEqual(store.load(), [])
    }
}
