import Foundation
import Testing

@testable import BelayPower

@Suite("Power environment")
struct PowerEnvironmentTests {
    @Test func snapshotIsSelfConsistentOnThisMachine() async {
        let monitor = PowerSourceMonitor()
        let snapshot = await monitor.current

        if let charge = snapshot.charge {
            #expect(charge >= 0 && charge <= 1)
        } else {
            // No battery reported means a desktop, which is always on AC.
            #expect(snapshot.isOnAC)
        }
        await monitor.stop()
    }

    @Test func pollIntervalCannotBreachTheWakeupBudget() async {
        let monitor = PowerSourceMonitor(interval: 1)
        #expect(await monitor.interval == PowerSourceMonitor.minimumInterval)
        await monitor.stop()
    }

    @Test func startAndStopAreIdempotent() async {
        let monitor = PowerSourceMonitor()
        await monitor.start()
        await monitor.start()
        await monitor.stop()
        await monitor.stop()
        #expect(await monitor.isRunning == false)
    }

    @Test func sleepEventsReachSubscribers() async {
        let observer = SystemSleepObserver()
        let events = await observer.events()

        await observer.report(.willSleep)
        await observer.report(.didWake)
        await observer.finish()

        var received: [SystemSleepEvent] = []
        for await event in events {
            received.append(event)
        }
        #expect(received == [.willSleep, .didWake])
        #expect(await observer.lastEvent == .didWake)
    }

    /// SIGUSR1 rather than SIGTERM: the mechanism is identical, and this avoids
    /// leaving the test process permanently ignoring its own kill signal.
    @Test func aTerminationSignalReleasesTheAssertion() async throws {
        let backend = MockPowerAssertionBackend()
        let controller = PowerAssertionController(backend: backend)
        await controller.hold(reason: "work", timeout: 3_600)

        let watch = TerminationSignalWatch()
        await watch.install(signals: [SIGUSR1], exitsProcess: false) {
            await controller.release()
        }
        raise(SIGUSR1)

        // A deadline rather than a fixed number of 5 ms naps: under load each
        // nap overruns, so counting naps quietly turns a 500 ms budget into
        // whatever the machine felt like.
        var released = false
        let deadline = Date().addingTimeInterval(10)
        while !released, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
            released = await controller.isHeld == false
        }

        #expect(released)
        #expect(await backend.liveIDs.isEmpty)
        await watch.cancel()
    }
}
