import Foundation
import Testing

@testable import BelayCore

/// A Stop that leaves background tasks running holds the session — bounded,
/// because the claim can never be re-verified by a later hook.
@Suite("Background tasks bracket")
struct BackgroundBracketTests {
    private func coordinator(_ clock: TestClock) -> ActivityCoordinator {
        ActivityCoordinator(clock: clock, policy: .default)
    }

    @Test("Background tasks outlive the freshness window and the TTL")
    func backgroundHolds() async {
        let clock = TestClock()
        let coordinator = coordinator(clock)

        await coordinator.ingest(
            .make(.working, at: clock.now, confidence: .exact, backgroundTasks: 2))
        clock.advance(60)
        await coordinator.ingest(.make(.idle, at: clock.now, confidence: .inferred))

        // Past both the 5-minute freshness window and the 10-minute TTL.
        clock.advance(15 * 60)
        await coordinator.evaluate()
        #expect(await coordinator.snapshot.activities[SessionID("s1")] == .working)
        #expect(await coordinator.snapshot.state.holdsAssertion)
    }

    @Test("The claim expires on its budget")
    func backgroundBudgetExpires() async {
        let clock = TestClock()
        let coordinator = coordinator(clock)

        await coordinator.ingest(
            .make(.working, at: clock.now, confidence: .exact, backgroundTasks: 1))
        clock.advance(AwakePolicy.backgroundTasksBudget + 60)
        await coordinator.evaluate()
        #expect(await coordinator.snapshot.activities[SessionID("s1")] != .working)
    }

    @Test("A Stop with zero tasks clears the bracket")
    func zeroClears() async {
        let clock = TestClock()
        let coordinator = coordinator(clock)

        await coordinator.ingest(
            .make(.working, at: clock.now, confidence: .exact, backgroundTasks: 3))
        clock.advance(60)
        await coordinator.ingest(
            .make(.idle, at: clock.now, confidence: .exact, backgroundTasks: 0))
        clock.advance(60)
        await coordinator.ingest(.make(.idle, at: clock.now, confidence: .inferred))

        clock.advance(6 * 60)
        await coordinator.evaluate()
        #expect(await coordinator.snapshot.activities[SessionID("s1")] == .idle)
    }

    /// Stop hooks are fire-and-forget and arrive reordered or twice. A stale
    /// one must neither clear a bracket a newer Stop armed nor resurrect one
    /// a newer Stop released — the same guard the rest of the exact state has.
    @Test("A stale Stop neither clears nor re-arms the bracket")
    func reorderedStopLeavesTheBracketAlone() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        var state = SessionState(
            id: SessionID("s1"), provider: .claudeCode, workspace: "acme-api", firstSeen: t0)

        state.record(.make(.working, at: t0 + 100, confidence: .exact, backgroundTasks: 2))
        state.record(.make(.idle, at: t0 + 90, confidence: .exact, backgroundTasks: 0))
        #expect(state.backgroundSince == t0 + 100, "the retried earlier Stop must not clear it")

        state.record(.make(.idle, at: t0 + 200, confidence: .exact, backgroundTasks: 0))
        state.record(.make(.working, at: t0 + 150, confidence: .exact, backgroundTasks: 3))
        #expect(state.backgroundSince == nil, "the stale busy Stop must not re-arm it")
    }
}
