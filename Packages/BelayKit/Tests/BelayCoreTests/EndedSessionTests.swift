import Foundation
import Testing

@testable import BelayCore

/// A session the hooks ended stays ended: the provider keeps following the
/// file and heartbeating for a while, and that must not bring it back.
@Suite("Ended sessions")
struct EndedSessionTests {
    private let session = SessionID("s1")

    @Test("A heartbeat after the end does not resurrect the session")
    func heartbeatDoesNotResurrect() async {
        let clock = TestClock()
        let coordinator = ActivityCoordinator(clock: clock, policy: .default)
        await coordinator.ingest(.make(.working, at: clock.now, confidence: .inferred))
        clock.advance(10)
        await coordinator.ingest(.make(.ended, at: clock.now, confidence: .exact))
        await coordinator.evaluate()
        #expect(await coordinator.snapshot.sessions.isEmpty)

        clock.advance(47)
        await coordinator.ingest(.make(.working, at: clock.now, confidence: .inferred, heartbeat: true))
        await coordinator.evaluate()
        #expect(await coordinator.snapshot.sessions.isEmpty)
    }

    /// Found live, in the shipped 2.1.0: a parked session idled, the TTL took
    /// it, the provider's silence heartbeat seeded it again as working, and
    /// the provider's own grace then ended it as one that went quiet.
    @Test("A heartbeat after a TTL eviction does not resurrect the session either")
    func heartbeatDoesNotResurrectAfterExpiry() async {
        let clock = TestClock()
        let coordinator = ActivityCoordinator(clock: clock, policy: .default)
        await coordinator.ingest(.make(.idle, at: clock.now, confidence: .exact))
        clock.advance(AwakePolicy.default.sessionTTL + AwakePolicy.default.awaitingUserBudget + 60)
        await coordinator.evaluate()
        #expect(await coordinator.snapshot.sessions.isEmpty)

        clock.advance(30)
        await coordinator.ingest(.make(.working, at: clock.now, confidence: .inferred, heartbeat: true))
        await coordinator.evaluate()
        #expect(await coordinator.snapshot.sessions.isEmpty)
    }

    @Test("A new prompt after the end is a new session")
    func promptRevives() async {
        let clock = TestClock()
        let coordinator = ActivityCoordinator(clock: clock, policy: .default)
        await coordinator.ingest(.make(.working, at: clock.now, confidence: .inferred))
        clock.advance(10)
        await coordinator.ingest(.make(.ended, at: clock.now, confidence: .exact))
        await coordinator.evaluate()

        clock.advance(47)
        await coordinator.ingest(.make(.working, at: clock.now, confidence: .inferred))
        await coordinator.evaluate()
        #expect(await coordinator.snapshot.activities[session] == .working)
    }

    @Test("The ending is forgotten after a while, so a late heartbeat counts again")
    func endingExpires() async {
        let clock = TestClock()
        let coordinator = ActivityCoordinator(clock: clock, policy: .default)
        await coordinator.ingest(.make(.ended, at: clock.now, confidence: .exact))
        await coordinator.evaluate()

        clock.advance(SessionLedger.endedMemory + 1)
        await coordinator.ingest(.make(.working, at: clock.now, confidence: .inferred, heartbeat: true))
        await coordinator.evaluate()
        #expect(await coordinator.snapshot.activities[session] == .working)
    }
}
