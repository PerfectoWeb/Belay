import Foundation
import Testing

@testable import BelayCore

/// A coordinator that parks inside `nextDeadline` until the test lets it go.
///
/// The real coordinator never suspends, so it can never hold the driver in the
/// window between reading the deadline and installing the sleeper — which is
/// exactly the window a nudge can fall into.
private actor GatedCoordinator: DrivableCoordinator {
    private(set) var evaluations = 0
    private var isOpen = false
    private var parked: CheckedContinuation<Void, Never>?
    private var arrival: CheckedContinuation<Void, Never>?

    var nextDeadline: Date? {
        get async {
            await gate()
            return nil
        }
    }

    @discardableResult
    func evaluate() -> AwakeDecision {
        evaluations += 1
        return .release
    }

    /// Resolves once the driver is parked in `nextDeadline`.
    func waitForParkedRead() async {
        guard parked == nil else { return }
        await withCheckedContinuation { arrival = $0 }
    }

    /// Lets the parked read through, and every later one straight past.
    func open() {
        isOpen = true
        parked?.resume()
        parked = nil
    }

    private func gate() async {
        guard !isOpen else { return }
        arrival?.resume()
        arrival = nil
        await withCheckedContinuation { parked = $0 }
    }
}

private actor SleepLog {
    private(set) var count = 0

    func note() {
        count += 1
    }
}

/// A clock whose sleep only ends when the task is cancelled, so "the driver
/// installed a sleeper" and "the driver re-evaluated" are trivially distinct.
private struct ParkingClock: Clock {
    let log = SleepLog()

    var now: Date { Date(timeIntervalSince1970: 1_700_000_000) }

    func sleep(until deadline: Date) async throws {
        // The sleeper task inherits the driver's isolation and cannot start
        // until the driver suspends, so a logged sleep means an installed one.
        await log.note()
        try await Task.sleep(for: .seconds(3_600))
    }
}

@Suite("CoordinatorDriver")
struct CoordinatorDriverTests {
    /// `BelayController.startProviders` ingests a signal and then nudges. If that
    /// nudge lands while the driver is reading the deadline it used to cancel a
    /// sleeper that did not exist yet, and the driver then slept on a deadline
    /// computed before the signal — up to a minute of an `.idle` or `.ended`
    /// signal going nowhere, which is the delay `nudge` exists to prevent.
    @Test("A nudge landing inside the deadline read is not lost")
    func nudgeInsideTheDeadlineReadIsNotLost() async {
        let coordinator = GatedCoordinator()
        let driver = CoordinatorDriver(coordinator: coordinator, clock: ParkingClock())
        await driver.start()
        await coordinator.waitForParkedRead()

        await driver.nudge()
        await coordinator.open()

        await settle("an evaluation") { await coordinator.evaluations >= 1 }
        #expect(await coordinator.evaluations >= 1)
        await driver.stop()
    }

    @Test("A nudge during the sleep still wakes the driver")
    func nudgeDuringTheSleepWakes() async {
        let coordinator = GatedCoordinator()
        await coordinator.open()
        let clock = ParkingClock()
        let driver = CoordinatorDriver(coordinator: coordinator, clock: clock)
        await driver.start()
        await settle("a sleeper") { await clock.log.count >= 1 }

        await driver.nudge()

        await settle("an evaluation") { await coordinator.evaluations >= 1 }
        #expect(await coordinator.evaluations >= 1)
        await driver.stop()
    }

    @Test("Stopping ends the loop")
    func stopEndsTheLoop() async {
        let coordinator = GatedCoordinator()
        await coordinator.open()
        let clock = ParkingClock()
        let driver = CoordinatorDriver(coordinator: coordinator, clock: clock)
        await driver.start()
        await settle("a sleeper") { await clock.log.count >= 1 }
        await driver.nudge()
        await settle("an evaluation") { await coordinator.evaluations >= 1 }

        await driver.stop()
        let after = await coordinator.evaluations
        for _ in 0..<200 { await Task.yield() }
        #expect(await coordinator.evaluations == after)
    }
}

/// Spins the cooperative pool until `condition` holds, so a test asserts on a
/// state the runtime has actually reached rather than on a wall-clock guess.
private func settle(_ what: String, until condition: () async -> Bool) async {
    for _ in 0..<20_000 {
        if await condition() { return }
        await Task.yield()
    }
    Issue.record("timed out waiting for \(what)")
}
