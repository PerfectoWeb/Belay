import Foundation
import Testing

@testable import BelayCore

@Suite("Always-on timer")
struct AlwaysOnTimerTests {
    private func alwaysOn() -> AwakePolicy {
        var policy = AwakePolicy.default
        policy.mode = .alwaysOn
        return policy
    }

    @Test("A timer holds until its deadline, then suspends and says why")
    func timerRunsOut() async {
        let clock = TestClock()
        let coordinator = ActivityCoordinator(clock: clock, policy: alwaysOn())

        await coordinator.setAlwaysOnTimer(900)
        #expect(await coordinator.evaluate().isHold)
        #expect(await coordinator.snapshot.timer?.duration == 900)

        clock.advance(901)
        #expect(await coordinator.evaluate() == .release)
        #expect(await coordinator.snapshot.state == .suspended(.timerEnded(900)))
        // The choice stays visible while the pause it caused is on screen.
        #expect(await coordinator.snapshot.timer?.duration == 900)
    }

    @Test("A restored live deadline keeps counting from where it was")
    func restoredTimerKeepsItsDeadline() async {
        let clock = TestClock()
        let coordinator = ActivityCoordinator(clock: clock, policy: alwaysOn())

        // Two minutes were left when the app died; two minutes stay left.
        await coordinator.restoreAlwaysOnTimer(duration: 900, deadline: clock.now + 120)
        #expect(await coordinator.evaluate().isHold)
        #expect(await coordinator.snapshot.timer?.duration == 900)

        clock.advance(121)
        #expect(await coordinator.evaluate() == .release)
        #expect(await coordinator.snapshot.state == .suspended(.timerEnded(900)))
    }

    @Test("A deadline that passed while the app was gone lands in the pause")
    func restoredExpiredTimerIsTheHonestPause() async {
        let clock = TestClock()
        let coordinator = ActivityCoordinator(clock: clock, policy: alwaysOn())

        await coordinator.restoreAlwaysOnTimer(duration: 900, deadline: clock.now - 60)
        #expect(await coordinator.evaluate() == .release)
        #expect(await coordinator.snapshot.state == .suspended(.timerEnded(900)))

        // And the pause keeps its one-click exit.
        await coordinator.holdAgain()
        #expect(await coordinator.evaluate().isHold)
    }

    @Test("Hold again starts a fresh round of the same length")
    func holdAgainRenewsTheTimer() async {
        let clock = TestClock()
        let coordinator = ActivityCoordinator(clock: clock, policy: alwaysOn())

        await coordinator.setAlwaysOnTimer(900)
        clock.advance(901)
        #expect(await coordinator.evaluate() == .release)

        await coordinator.holdAgain()
        #expect(await coordinator.evaluate().isHold)
        #expect(await coordinator.snapshot.timer?.deadline == clock.now + 900)
    }

    @Test("Hold again forgives a tripped cap")
    func holdAgainForgivesTheCap() async {
        let clock = TestClock()
        var policy = alwaysOn()
        policy.maxContinuousAwake = 600
        let coordinator = ActivityCoordinator(clock: clock, policy: policy)

        #expect(await coordinator.evaluate().isHold)
        clock.advance(601)
        #expect(await coordinator.evaluate() == .release)
        #expect(await coordinator.snapshot.state == .suspended(.maxDurationReached(600)))

        await coordinator.holdAgain()
        #expect(await coordinator.evaluate().isHold)
    }

    @Test("Coming back to the machine re-arms the cap but not the timer")
    func returnRenewsCapOnly() async {
        let clock = TestClock()
        var policy = alwaysOn()
        policy.maxContinuousAwake = 600
        let coordinator = ActivityCoordinator(clock: clock, policy: policy)

        #expect(await coordinator.evaluate().isHold)
        clock.advance(601)
        #expect(await coordinator.evaluate() == .release)

        await coordinator.renewCapOnReturn()
        #expect(await coordinator.evaluate().isHold, "a returned human sanctions a fresh cap cycle")

        await coordinator.setAlwaysOnTimer(900)
        clock.advance(901)
        #expect(await coordinator.evaluate() == .release)
        await coordinator.renewCapOnReturn()
        #expect(
            await coordinator.evaluate() == .release,
            "a finished timer is a fulfilled request, not a tripped guard")
    }

    @Test("Leaving Always on ends the timer; coming back starts unbounded")
    func modeSwitchClearsTheTimer() async {
        let clock = TestClock()
        let coordinator = ActivityCoordinator(clock: clock, policy: alwaysOn())
        await coordinator.setAlwaysOnTimer(900)

        var auto = AwakePolicy.default
        auto.mode = .auto
        await coordinator.setPolicy(auto)
        #expect(await coordinator.snapshot.timer == nil)

        await coordinator.setPolicy(alwaysOn())
        #expect(await coordinator.evaluate().isHold)
        #expect(await coordinator.snapshot.timer == nil, "a stale countdown must not resume")
        #expect(await coordinator.snapshot.state == .alwaysOn)
    }

    @Test("The driver's next deadline includes the timer")
    func nextDeadlineSeesTheTimer() async {
        let clock = TestClock()
        let coordinator = ActivityCoordinator(clock: clock, policy: alwaysOn())
        await coordinator.setAlwaysOnTimer(900)
        // Inside the grace window, so the grace and cap candidates are both
        // further out and the timer is what the driver must wake for.
        clock.advance(850)
        await coordinator.evaluate()
        #expect(await coordinator.nextDeadline == clock.now + 50)
    }

    @Test("When both bounds have passed, the user's own timer names the pause")
    func timerOutranksTheCap() async {
        let clock = TestClock()
        var policy = alwaysOn()
        policy.maxContinuousAwake = 600
        let coordinator = ActivityCoordinator(clock: clock, policy: policy)

        await coordinator.setAlwaysOnTimer(600)
        clock.advance(601)
        await coordinator.evaluate()
        #expect(await coordinator.snapshot.state == .suspended(.timerEnded(600)))
    }
}
