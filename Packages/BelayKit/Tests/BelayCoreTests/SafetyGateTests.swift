import Foundation
import Testing

@testable import BelayCore

@Suite("Safety gates")
struct SafetyGateTests {
    @Test("The max-duration cap fires mid-work and says why")
    func maxDurationCap() async {
        let clock = TestClock()
        var policy = AwakePolicy.default
        policy.maxContinuousAwake = 600
        policy.sessionTTL = 7200
        let coordinator = ActivityCoordinator(clock: clock, policy: policy)

        #expect(await coordinator.ingest(.make(.working, at: clock.now)).isHold)

        clock.advance(601)
        await coordinator.ingest(.make(.working, at: clock.now))
        #expect(await coordinator.evaluate() == .release)
        #expect(await coordinator.snapshot.state == .suspended(.maxDurationReached(600)))
    }

    /// A backwards wall-clock step (an NTP correction) makes a fresh reading
    /// look like the future, so it never ages out and the hold outlasts its
    /// cause. The coordinator treats a jump back like a wake: it forgets the
    /// meaningless timestamps and re-derives, rather than over-holding.
    @Test("A backwards clock step forgets stale future timestamps, not over-holds")
    func backwardsClockStepResyncs() async {
        let clock = TestClock()
        var policy = AwakePolicy.default
        policy.sessionTTL = 600
        let coordinator = ActivityCoordinator(clock: clock, policy: policy)

        #expect(await coordinator.ingest(.make(.working, at: clock.now)).isHold)

        // The clock jumps back five minutes with no new signal.
        clock.advance(-300)
        #expect(await coordinator.evaluate() == .release)
        #expect(await coordinator.snapshot.sessions.isEmpty)
    }

    /// A jitter under the threshold is not a correction and must not wipe live
    /// state — the working session keeps holding.
    @Test("A sub-threshold backwards jitter does not wipe state")
    func subThresholdJitterHolds() async {
        let clock = TestClock()
        let coordinator = ActivityCoordinator(clock: clock, policy: .default)
        #expect(await coordinator.ingest(.make(.working, at: clock.now)).isHold)
        clock.advance(-1)
        #expect(await coordinator.evaluate().isHold)
        #expect(await coordinator.snapshot.sessions.isEmpty == false)
    }

    /// A wake from sleep must not count the hours the Mac spent asleep toward
    /// the awake limit. `resync` restarts the cap clock, so Always on holds
    /// fresh after a wake instead of suspending the instant it comes back.
    @Test("A wake from sleep gives Always on a fresh cap cycle, not an instant suspend")
    func resyncRestartsTheCapClock() async {
        let clock = TestClock()
        var policy = AwakePolicy.default
        policy.mode = .alwaysOn
        policy.maxContinuousAwake = 600
        let coordinator = ActivityCoordinator(clock: clock, policy: policy)

        #expect(await coordinator.evaluate().isHold)

        // The Mac sleeps for well past the cap; no evaluate runs while asleep.
        clock.advance(3600)
        await coordinator.resync()

        // It must not suspend on the accumulated sleep time.
        #expect(await coordinator.snapshot.state == .alwaysOn)
        #expect(await coordinator.evaluate().isHold)

        // Still inside the fresh post-wake cap: holding.
        clock.advance(599)
        #expect(await coordinator.evaluate().isHold)

        // Past the fresh cap: now it caps, honestly.
        clock.advance(2)
        #expect(await coordinator.evaluate() == .release)
        #expect(await coordinator.snapshot.state == .suspended(.maxDurationReached(600)))
    }

    @Test("After the cap fires it stays released while the same work continues")
    func capDoesNotReArmWhileWorkContinues() async {
        let clock = TestClock()
        var policy = AwakePolicy.default
        policy.maxContinuousAwake = 600
        policy.sessionTTL = 7200
        let coordinator = ActivityCoordinator(clock: clock, policy: policy)

        await coordinator.ingest(.make(.working, at: clock.now))
        clock.advance(601)
        await coordinator.evaluate()

        for _ in 0..<5 {
            clock.advance(30)
            await coordinator.ingest(.make(.working, at: clock.now))
            #expect(await coordinator.evaluate() == .release, "cap must not re-arm under continuous work")
        }
    }

    @Test("The cap resets once work actually stops, and a later run holds again")
    func capResetsAfterWorkStops() async {
        let clock = TestClock()
        var policy = AwakePolicy.default
        policy.maxContinuousAwake = 600
        policy.sessionTTL = 7200
        let coordinator = ActivityCoordinator(clock: clock, policy: policy)

        await coordinator.ingest(.make(.working, at: clock.now))
        clock.advance(601)
        await coordinator.evaluate()

        await coordinator.ingest(.make(.idle, at: clock.now))
        clock.advance(policy.gracePeriod + 1)
        #expect(await coordinator.evaluate() == .release)

        await coordinator.ingest(.make(.working, at: clock.now))
        #expect(await coordinator.evaluate().isHold, "a fresh run must be allowed to hold")
    }

    @Test("The battery guard trips below the floor and recovers on AC")
    func batteryGuard() async {
        let clock = TestClock()
        let coordinator = ActivityCoordinator(clock: clock, policy: .default)
        await coordinator.ingest(.make(.working, at: clock.now))

        await coordinator.setPowerConditions(
            PowerConditions(isOnAC: false, charge: 0.10, isLowPowerMode: false)
        )
        #expect(await coordinator.evaluate() == .release)
        #expect(await coordinator.snapshot.state == .suspended(.batteryLow(charge: 0.10)))

        await coordinator.setPowerConditions(
            PowerConditions(isOnAC: true, charge: 0.10, isLowPowerMode: false)
        )
        #expect(await coordinator.evaluate().isHold, "plugging in must restore the hold")
    }

    @Test("A low battery on AC power does not trip the guard")
    func batteryGuardIgnoresACPower() async {
        let clock = TestClock()
        let coordinator = ActivityCoordinator(clock: clock, policy: .default)
        await coordinator.setPowerConditions(
            PowerConditions(isOnAC: true, charge: 0.02, isLowPowerMode: false)
        )
        #expect(await coordinator.ingest(.make(.working, at: clock.now)).isHold)
    }

    @Test("Low Power Mode shortens the grace period without stopping work")
    func lowPowerShortensGrace() async {
        let clock = TestClock()
        let coordinator = ActivityCoordinator(clock: clock, policy: .default)
        await coordinator.setPowerConditions(
            PowerConditions(isOnAC: true, charge: nil, isLowPowerMode: true)
        )
        await coordinator.ingest(.make(.working, at: clock.now))
        await coordinator.ingest(.make(.idle, at: clock.now))

        clock.advance(AwakePolicy.default.effectiveGrace(lowPower: true) + 1)
        #expect(await coordinator.evaluate() == .release)
        #expect(AwakePolicy.default.effectiveGrace(lowPower: true) < AwakePolicy.default.gracePeriod)
    }

    @Test("Off mode holds nothing no matter what arrives")
    func offModeNeverHolds() async {
        let clock = TestClock()
        var policy = AwakePolicy.default
        policy.mode = .off
        let coordinator = ActivityCoordinator(clock: clock, policy: policy)

        #expect(await coordinator.ingest(.make(.working, at: clock.now)) == .release)
        #expect(await coordinator.ingest(.make(.awaitingUser, at: clock.now)) == .release)
        #expect(await coordinator.snapshot.state == .off)
    }

    @Test("Always-on holds with no sessions at all, and still obeys the battery guard")
    func alwaysOnMode() async {
        let clock = TestClock()
        var policy = AwakePolicy.default
        policy.mode = .alwaysOn
        let coordinator = ActivityCoordinator(clock: clock, policy: policy)

        #expect(await coordinator.evaluate().isHold)
        #expect(await coordinator.snapshot.state == .alwaysOn)

        await coordinator.setPowerConditions(
            PowerConditions(isOnAC: false, charge: 0.05, isLowPowerMode: false)
        )
        #expect(await coordinator.evaluate() == .release)
    }

    @Test("Switching mode to off while holding releases immediately")
    func modeSwitchReleasesAtOnce() async {
        let clock = TestClock()
        let coordinator = ActivityCoordinator(clock: clock, policy: .default)
        #expect(await coordinator.ingest(.make(.working, at: clock.now)).isHold)

        var policy = AwakePolicy.default
        policy.mode = .off
        await coordinator.setPolicy(policy)
        #expect(await coordinator.evaluate() == .release)
    }
}
