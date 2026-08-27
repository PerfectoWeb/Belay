import Foundation
import Testing

@testable import BelayCore

@Suite("Signal fusion")
struct FusionTests {
    /// The bug docs/03 names explicitly: a hook says the turn is done, a trailing
    /// disk flush says it is still writing, and the two fight forever.
    @Test("A fresh exact idle beats a later inferred working for the same session")
    func exactIdleBeatsLateInferredWorking() async {
        let clock = TestClock()
        let coordinator = ActivityCoordinator(clock: clock, policy: .default)

        await coordinator.ingest(.make(.working, at: clock.now, confidence: .inferred))
        clock.advance(1)
        await coordinator.ingest(.make(.idle, at: clock.now, confidence: .exact))
        clock.advance(1)
        await coordinator.ingest(.make(.working, at: clock.now, confidence: .inferred))

        let session = SessionID("s1")
        #expect(await coordinator.snapshot.activities[session] == .idle)
        #expect(await coordinator.snapshot.state == .coolingDown)
    }

    @Test("Once hooks go stale the inferred signal takes over again")
    func inferredResumesWhenExactGoesStale() async {
        let clock = TestClock()
        var policy = AwakePolicy.default
        policy.sessionTTL = 3600
        let coordinator = ActivityCoordinator(clock: clock, policy: policy)

        await coordinator.ingest(.make(.idle, at: clock.now, confidence: .exact))
        clock.advance(1)
        await coordinator.ingest(.make(.working, at: clock.now, confidence: .inferred))
        #expect(await coordinator.snapshot.activities[SessionID("s1")] == .idle)

        clock.advance(policy.hookFreshnessWindow + 1)
        await coordinator.evaluate()
        #expect(await coordinator.snapshot.activities[SessionID("s1")] == .working)
    }

    /// The freshness crossing feeds `nextDeadline` so the driver wakes exactly
    /// when the fused activity flips, instead of at its 60 s safety tick.
    @Test("The exact-freshness deadline marks where the fused activity flips")
    func exactFreshnessDeadlineMarksTheCrossing() {
        let base = Date(timeIntervalSince1970: 1000)
        var session = SessionState(
            id: SessionID("s1"), provider: .claudeCode, workspace: nil, firstSeen: base)
        session.record(.make(.working, at: base, confidence: .exact))
        session.record(.make(.idle, at: base, confidence: .inferred))
        #expect(
            session.exactFreshnessDeadline(window: 300, toolCallBudget: .infinity)
                == base.addingTimeInterval(300))

        // Agreeing readings: the crossing changes nothing, so there is none.
        session.record(.make(.working, at: base, confidence: .inferred))
        #expect(session.exactFreshnessDeadline(window: 300, toolCallBudget: .infinity) == nil)

        // Only an exact reading: nothing to fall back to when it goes stale.
        var lone = SessionState(
            id: SessionID("s2"), provider: .claudeCode, workspace: nil, firstSeen: base)
        lone.record(.make(.working, at: base, confidence: .exact))
        #expect(lone.exactFreshnessDeadline(window: 300, toolCallBudget: .infinity) == nil)
    }

    @Test("ended wins over everything, from either tier")
    func endedAlwaysWins() {
        let now = Date()
        var session = SessionState(id: SessionID("s1"), provider: .claudeCode, workspace: nil, firstSeen: now)
        session.record(.make(.ended, at: now, confidence: .inferred))
        session.record(.make(.working, at: now + 5, confidence: .exact))

        #expect(session.effectiveActivity(now: now + 5, freshness: 300) == .ended)
    }

    @Test("Out-of-order delivery within a tier is ignored, not applied")
    func staleSignalIgnored() {
        let now = Date()
        var session = SessionState(id: SessionID("s1"), provider: .claudeCode, workspace: nil, firstSeen: now)
        session.record(.make(.working, at: now + 10, confidence: .inferred))
        session.record(.make(.idle, at: now + 1, confidence: .inferred))

        #expect(session.effectiveActivity(now: now + 10, freshness: 300) == .working)
    }

    @Test("A workspace name arriving later fills in a session that had none")
    func workspaceBackfilled() {
        let now = Date()
        var session = SessionState(id: SessionID("s1"), provider: .claudeCode, workspace: nil, firstSeen: now)
        session.record(.make(.working, at: now, confidence: .exact, workspace: nil))
        session.record(.make(.working, at: now + 1, confidence: .exact, workspace: "acme-api"))

        #expect(session.workspace == "acme-api")
    }
}

/// R6, the risk the whole hook tier exists to close: a tool call that runs for
/// half an hour writes nothing, so every inferred reading calls the turn over.
@Suite("Open tool calls")
struct ToolCallBracketTests {
    private func coordinator(_ clock: TestClock) -> ActivityCoordinator {
        ActivityCoordinator(clock: clock, policy: .default)
    }

    @Test("A tool call still running outranks the file watcher long after the hook")
    func openBracketOutlivesFreshness() async {
        let clock = TestClock()
        let coordinator = coordinator(clock)

        await coordinator.ingest(.make(.working, at: clock.now, confidence: .exact, toolCall: .opened))
        clock.advance(60)
        // What the transcript says while a test suite runs: nothing new, so the
        // sweep calls it finished.
        await coordinator.ingest(.make(.idle, at: clock.now, confidence: .inferred))

        clock.advance(30 * 60)
        await coordinator.evaluate()
        #expect(await coordinator.snapshot.activities[SessionID("s1")] == .working)
        #expect(await coordinator.snapshot.state.holdsAssertion)
    }

    @Test("The tool returning hands the session back to the file watcher")
    func closedBracketReleases() async {
        let clock = TestClock()
        let coordinator = coordinator(clock)

        await coordinator.ingest(.make(.working, at: clock.now, confidence: .exact, toolCall: .opened))
        clock.advance(30 * 60)
        await coordinator.ingest(.make(.idle, at: clock.now, confidence: .exact, toolCall: .closed))

        clock.advance(1)
        await coordinator.evaluate()
        #expect(await coordinator.snapshot.activities[SessionID("s1")] == .idle)
    }

    /// An agent killed between the two hooks fires neither, and a bracket with
    /// nobody left to close it must not hold the Mac for the awake limit.
    @Test("A bracket nobody closed expires on its own budget")
    func lostBracketExpires() async {
        let clock = TestClock()
        let coordinator = coordinator(clock)

        await coordinator.ingest(.make(.working, at: clock.now, confidence: .exact, toolCall: .opened))
        clock.advance(60)
        await coordinator.ingest(.make(.idle, at: clock.now, confidence: .inferred))

        clock.advance(AwakePolicy.openToolCallBudget + 60)
        await coordinator.evaluate()
        #expect(await coordinator.snapshot.activities[SessionID("s1")] != .working)
    }

    /// The session TTL is ten minutes and a tool call emits nothing, so without
    /// the exemption the ledger evicts the session the bracket is protecting.
    @Test("A bracketed session is not evicted while it runs")
    func bracketSurvivesSessionTTL() async {
        let clock = TestClock()
        let coordinator = coordinator(clock)

        await coordinator.ingest(.make(.working, at: clock.now, confidence: .exact, toolCall: .opened))
        clock.advance(AwakePolicy.default.sessionTTL + 5 * 60)
        await coordinator.evaluate()

        #expect(await coordinator.snapshot.activities[SessionID("s1")] == .working)
    }

    /// A hook that arrives out of order is normal; one that closes a bracket a
    /// newer hook already opened would sleep the Mac mid-tool.
    @Test("A late close does not undo a newer open")
    func lateCloseIgnored() async {
        let clock = TestClock()
        let coordinator = coordinator(clock)
        let stale = clock.now

        clock.advance(10)
        await coordinator.ingest(.make(.working, at: clock.now, confidence: .exact, toolCall: .opened))
        await coordinator.ingest(.make(.idle, at: stale, confidence: .exact, toolCall: .closed))
        await coordinator.ingest(.make(.idle, at: clock.now, confidence: .inferred))

        clock.advance(20 * 60)
        await coordinator.evaluate()
        #expect(await coordinator.snapshot.activities[SessionID("s1")] == .working)
    }
}
