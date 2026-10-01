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
        clock.advance(SessionState.inferredLead + 1)
        await coordinator.ingest(.make(.working, at: clock.now, confidence: .inferred))
        #expect(await coordinator.snapshot.activities[SessionID("s1")] == .idle)

        clock.advance(policy.hookFreshnessWindow + 1)
        await coordinator.evaluate()
        #expect(await coordinator.snapshot.activities[SessionID("s1")] == .working)
    }

    /// Found live: a session parked on a tool call that waits for a wake-up.
    /// Its Stop said idle, its transcript's last record looks like a tool
    /// call under way, and nothing was written after the Stop.
    @Test("A stale exact idle still beats an inferred working that is no newer")
    func staleExactKeepsTheLastWord() async {
        let clock = TestClock()
        var policy = AwakePolicy.default
        policy.sessionTTL = 3600
        let coordinator = ActivityCoordinator(clock: clock, policy: policy)

        await coordinator.ingest(.make(.working, at: clock.now, confidence: .inferred))
        clock.advance(1)
        await coordinator.ingest(.make(.idle, at: clock.now, confidence: .exact))
        clock.advance(1)
        await coordinator.ingest(.make(.working, at: clock.now, confidence: .inferred))

        clock.advance(policy.hookFreshnessWindow + 1)
        await coordinator.evaluate()
        #expect(await coordinator.snapshot.activities[SessionID("s1")] == .idle)
    }

    /// The freshness crossing feeds `nextDeadline` so the driver wakes exactly
    /// when the fused activity flips, instead of at its 60 s safety tick.
    /// Found live, second try: the harness flushes the transcript after the
    /// Stop, and the provider reports those bytes as a heartbeat with a new
    /// date, which used to outrank the hook once it was stale.
    @Test("A heartbeat after a stale exact idle keeps the session alive but idle")
    func heartbeatDoesNotReviveAParkedSession() async {
        let clock = TestClock()
        let coordinator = ActivityCoordinator(clock: clock, policy: .default)

        await coordinator.ingest(.make(.working, at: clock.now, confidence: .inferred))
        clock.advance(1)
        await coordinator.ingest(.make(.idle, at: clock.now, confidence: .exact))
        clock.advance(30)
        await coordinator.ingest(.make(.working, at: clock.now, confidence: .inferred, heartbeat: true))

        clock.advance(AwakePolicy.default.hookFreshnessWindow + 1)
        await coordinator.evaluate()
        let session = SessionID("s1")
        #expect(await coordinator.snapshot.activities[session] == .idle)
        #expect(
            await coordinator.snapshot.sessions.contains { $0.id == session },
            "the heartbeat counts for the TTL")

        clock.advance(AwakePolicy.default.sessionTTL + 1)
        await coordinator.evaluate()
        #expect(await coordinator.snapshot.sessions.contains { $0.id == session } == false)
    }

    @Test("A heartbeat is the first reading of a session adopted mid-turn")
    func heartbeatSeedsAnUnreadSession() {
        let now = Date()
        var session = SessionState(id: SessionID("s1"), provider: .claudeCode, workspace: nil, firstSeen: now)
        session.record(.make(.working, at: now, confidence: .inferred, heartbeat: true))
        #expect(session.effectiveActivity(now: now, freshness: 300) == .working)

        session.record(.make(.idle, at: now + 1, confidence: .exact))
        session.record(.make(.working, at: now + 2, confidence: .inferred, heartbeat: true))
        #expect(session.effectiveActivity(now: now + 1000, freshness: 300) == .idle)
        #expect(session.lastSignal == now + 2)
    }

    @Test("The exact-freshness deadline marks where the fused activity flips")
    func exactFreshnessDeadlineMarksTheCrossing() {
        let base = Date(timeIntervalSince1970: 1000)
        var session = SessionState(
            id: SessionID("s1"), provider: .claudeCode, workspace: nil, firstSeen: base)
        session.record(.make(.working, at: base, confidence: .exact))
        let later = base.addingTimeInterval(SessionState.inferredLead + 1)
        session.record(.make(.idle, at: later, confidence: .inferred))
        #expect(
            session.exactFreshnessDeadline(window: 300, toolCallBudget: .infinity)
                == base.addingTimeInterval(300))

        // Agreeing readings: the crossing changes nothing, so there is none.
        session.record(.make(.working, at: later, confidence: .inferred))
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
