import Foundation
import Testing

@testable import VigilCore

/// docs/08 asks for thousands of random signal sequences checked against the
/// invariants rather than a handful of hand-picked paths. The generator is
/// seeded so a failure is reproducible from the seed printed in the message.
@Suite("Coordinator invariants under random input")
struct CoordinatorPropertyTests {
    private static let activities: [SessionActivity] = [.working, .idle, .awaitingUser, .ended]
    private static let modes: [AwakeMode] = [.auto, .auto, .auto, .alwaysOn, .off]

    @Test("Random sequences never break the hold invariants", arguments: 0..<40)
    func randomSequences(seed: UInt64) async {
        var rng = SeededGenerator(seed: seed &+ 1)
        let clock = TestClock()
        var policy = AwakePolicy.default
        policy.maxContinuousAwake = Bool.random(using: &rng) ? 900 : nil
        let coordinator = ActivityCoordinator(clock: clock, policy: policy)

        for _ in 0..<120 {
            await step(coordinator, policy: &policy, clock: clock, rng: &rng)

            clock.advance(Double.random(in: 0...45, using: &rng))
            let decision = await coordinator.evaluate()
            let snapshot = await coordinator.snapshot

            // The assertion the whole product rests on: what we told the power
            // layer and what we show the user can never disagree.
            #expect(
                snapshot.state.holdsAssertion == decision.isHold,
                "state \(snapshot.state) disagrees with decision (seed \(seed))"
            )
            #expect(
                (snapshot.holdReason != nil) == decision.isHold,
                "a hold must always carry a reason (seed \(seed))"
            )
            if case .off = snapshot.state {
                #expect(!decision.isHold, "off mode must never hold (seed \(seed))")
            }
        }

        // Emission is on change only, so the stream must never repeat a release.
        let stream = await coordinator.decisions()
        await coordinator.shutdown()
        var previousWasRelease = false
        for await decision in stream {
            #expect(!(previousWasRelease && decision == .release), "duplicate release emitted")
            previousWasRelease = decision == .release
        }
    }

    /// One random mutation: a mode change, a power change, a resync, or a signal.
    private func step(
        _ coordinator: ActivityCoordinator,
        policy: inout AwakePolicy,
        clock: TestClock,
        rng: inout SeededGenerator
    ) async {
        switch Int.random(in: 0..<10, using: &rng) {
        case 0:
            policy.mode = Self.modes.randomElement(using: &rng) ?? .auto
            await coordinator.setPolicy(policy)
        case 1:
            await coordinator.setPowerConditions(
                PowerConditions(
                    isOnAC: Bool.random(using: &rng),
                    charge: Double.random(in: 0...1, using: &rng),
                    isLowPowerMode: Bool.random(using: &rng)
                )
            )
        case 2:
            await coordinator.resync()
        default:
            await coordinator.ingest(
                .make(
                    Self.activities.randomElement(using: &rng) ?? .idle,
                    session: "s\(Int.random(in: 0..<4, using: &rng))",
                    at: clock.now,
                    confidence: Bool.random(using: &rng) ? .exact : .inferred
                )
            )
        }
    }

    @Test("A session is never resurrected after its TTL expires")
    func expiredSessionsStayGone() async {
        var rng = SeededGenerator(seed: 99)
        let clock = TestClock()
        let coordinator = ActivityCoordinator(clock: clock, policy: .default)

        for index in 0..<200 {
            await coordinator.ingest(
                .make(.working, session: "s\(index % 3)", at: clock.now, confidence: .inferred)
            )
            clock.advance(Double.random(in: 0...30, using: &rng))
            await coordinator.evaluate()

            let now = clock.now
            for session in await coordinator.snapshot.sessions {
                #expect(
                    now.timeIntervalSince(session.lastSignal) <= AwakePolicy.default.sessionTTL,
                    "an expired session survived pruning"
                )
            }
        }
    }
}
