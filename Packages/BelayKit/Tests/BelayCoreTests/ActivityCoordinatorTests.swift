import Foundation
import Testing

@testable import BelayCore

@Suite("Coordinator lifecycle")
struct ActivityCoordinatorTests {
    @Test("A single session: working holds, idle keeps holding through grace, then releases")
    func singleSessionThroughGrace() async {
        let clock = TestClock()
        let coordinator = ActivityCoordinator(clock: clock, policy: .default)

        #expect(await coordinator.ingest(.make(.working, at: clock.now)).isHold)

        clock.advance(30)
        await coordinator.ingest(.make(.idle, at: clock.now))
        #expect(await coordinator.evaluate().isHold, "grace period must still hold")
        #expect(await coordinator.snapshot.state == .coolingDown)

        clock.advance(AwakePolicy.default.gracePeriod + 1)
        #expect(await coordinator.evaluate() == .release)
        #expect(await coordinator.snapshot.state == .armed)
    }

    @Test("Two sessions: one idle, one working, still held")
    func twoSessionsOneWorking() async {
        let clock = TestClock()
        let coordinator = ActivityCoordinator(clock: clock, policy: .default)

        await coordinator.ingest(.make(.working, session: "a", at: clock.now))
        await coordinator.ingest(.make(.working, session: "b", at: clock.now))
        clock.advance(10)
        await coordinator.ingest(.make(.idle, session: "a", at: clock.now))

        let decision = await coordinator.evaluate()
        #expect(decision.isHold)
        #expect(await coordinator.snapshot.state == .working)

        // The reason must not name a workspace while several sessions are up.
        if case .working(let count, let workspace) = await coordinator.snapshot.holdReason {
            #expect(count == 1)
            #expect(workspace == "acme-api")
        } else {
            Issue.record("expected a working hold reason")
        }
    }

    @Test("A session that goes silent forever is evicted at TTL and the hold drops")
    func silentSessionEvicted() async {
        let clock = TestClock()
        let coordinator = ActivityCoordinator(clock: clock, policy: .default)
        await coordinator.ingest(.make(.working, at: clock.now))

        clock.advance(AwakePolicy.default.sessionTTL + 1)
        #expect(await coordinator.evaluate() == .release)
        #expect(await coordinator.snapshot.sessions.isEmpty)
    }

    @Test("An ended session is dropped immediately, not at TTL")
    func endedSessionDroppedAtOnce() async {
        let clock = TestClock()
        let coordinator = ActivityCoordinator(clock: clock, policy: .default)
        await coordinator.ingest(.make(.working, at: clock.now))
        clock.advance(1)
        await coordinator.ingest(.make(.ended, at: clock.now))

        #expect(await coordinator.snapshot.sessions.isEmpty)
        // Still cooling down: the process died, but work may resume shortly.
        #expect(await coordinator.evaluate().isHold)

        clock.advance(AwakePolicy.default.gracePeriod + 1)
        #expect(await coordinator.evaluate() == .release)
    }

    /// docs/02's diagram routes an expired awaiting budget through CoolingDown.
    /// PRD R7 calls the budget a bounded window after which Belay gives up, and
    /// stacking another grace period on top of a 15-minute wait contradicts that,
    /// so the budget releases directly. Recorded in PROJECT_STATE.md as D8.
    @Test("awaitingUser holds, then gives up the moment its budget expires")
    func awaitingUserBudget() async {
        let clock = TestClock()
        let coordinator = ActivityCoordinator(clock: clock, policy: .default)

        await coordinator.ingest(.make(.awaitingUser, at: clock.now))
        #expect(await coordinator.snapshot.state == .awaitingUser)

        clock.advance(AwakePolicy.default.awaitingUserBudget - 1)
        #expect(await coordinator.evaluate().isHold)

        clock.advance(2)
        #expect(await coordinator.evaluate() == .release)
        #expect(await coordinator.snapshot.state == .armed)
    }

    @Test("Work following an awaiting prompt still gets the normal grace tail")
    func workAfterAwaitingKeepsGrace() async {
        let clock = TestClock()
        let coordinator = ActivityCoordinator(clock: clock, policy: .default)

        await coordinator.ingest(.make(.awaitingUser, at: clock.now))
        clock.advance(5)
        await coordinator.ingest(.make(.working, at: clock.now))
        clock.advance(5)
        await coordinator.ingest(.make(.idle, at: clock.now))

        #expect(await coordinator.evaluate().isHold)
        clock.advance(AwakePolicy.default.gracePeriod + 1)
        #expect(await coordinator.evaluate() == .release)
    }

    @Test("Rapid flapping produces exactly one hold and one release")
    func flappingEmitsOnce() async {
        let clock = TestClock()
        let coordinator = ActivityCoordinator(clock: clock, policy: .default)
        let stream = await coordinator.decisions()

        let collector = Task { await stream.reduce(into: [AwakeDecision]()) { $0.append($1) } }

        for _ in 0..<50 {
            await coordinator.ingest(.make(.working, at: clock.now))
            clock.advance(0.1)
            await coordinator.ingest(.make(.idle, at: clock.now))
            clock.advance(0.1)
        }
        clock.advance(AwakePolicy.default.gracePeriod + 1)
        await coordinator.evaluate()
        await coordinator.shutdown()

        let decisions = await collector.value
        #expect(decisions.count == 2, "expected one hold and one release, got \(decisions.count)")
        #expect(decisions.first?.isHold == true)
        #expect(decisions.last == .release)
    }

    @Test("resync forgets everything, as required after a wake from sleep")
    func resyncClearsState() async {
        let clock = TestClock()
        let coordinator = ActivityCoordinator(clock: clock, policy: .default)
        await coordinator.ingest(.make(.working, at: clock.now))

        await coordinator.resync()
        #expect(await coordinator.snapshot.sessions.isEmpty)
        #expect(await coordinator.evaluate() == .release)
    }
}
