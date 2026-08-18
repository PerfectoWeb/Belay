import AppKit
import BelayCore
import BelayPower

/// The two observers that watch the machine itself: the power source and
/// sleep/wake. Beside `BelayController` rather than inside it for one dull
/// reason: that file is at the length the linter allows.
extension BelayController {
    func observePowerSource() {
        tasks.append(
            Task { [powerSource, coordinator, driver, weak self] in
                for await snapshot in await powerSource.changes() {
                    await coordinator.setPowerConditions(
                        PowerConditions(
                            isOnAC: snapshot.isOnAC,
                            charge: snapshot.charge,
                            isLowPowerMode: snapshot.isLowPowerMode
                        )
                    )
                    // AC and battery carry different display-sleep delays, and
                    // the dimmer keys off whichever is live.
                    self?.nightDimming.isOnAC = snapshot.isOnAC
                    await driver.nudge()
                }
            }
        )
    }

    func observeSleepWake() {
        sleepObservers = SleepWakeForwarding.install(into: sleepObserver)

        tasks.append(
            Task { [sleepObserver, assertions, coordinator, weak self] in
                for await event in await sleepObserver.events() {
                    switch event {
                    case .willSleep:
                        await assertions.release()
                    case .didWake:
                        // Every timestamp we hold predates the sleep and is
                        // meaningless now; re-derive from scratch (docs/04).
                        await coordinator.resync()
                    }
                    self?.refreshSnapshot()
                }
            }
        )
    }
}
