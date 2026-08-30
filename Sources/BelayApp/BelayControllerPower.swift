import AppKit
import BelayCore
import BelayPower

/// The two observers that watch the machine itself: the power source and
/// sleep/wake. Beside `BelayController` rather than inside it for one dull
/// reason: that file is at the length the linter allows.
extension BelayController {
    /// SIGTERM/SIGINT: drop the assertion (invariant 4) and bank the run in
    /// progress. The signal handler calls `exit(0)` before the graceful
    /// `shutdown()` flush can run, so `killall Belay` would otherwise lose an
    /// overnight hold from the statistics.
    func installTerminationHandler() {
        tasks.append(
            Task { [signals, assertions, weak self] in
                await signals.install { [weak self] in
                    await assertions.release()
                    await self?.bankUsageOnTermination()
                    // The goodbye the next launch reads a kill by: this path
                    // exits before `applicationWillTerminate` can write it.
                    Diagnostics.appendFromAnywhere("collection off")
                }
            })
    }

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
        // Append, not assign: `observeHumanReturn()` runs first and has already
        // put the screensDidWake token in here. Assigning over the array
        // dropped that token, so `shutdown()` could never remove the observer
        // and it kept firing renewCapOnReturn after teardown.
        sleepObservers.append(contentsOf: SleepWakeForwarding.install(into: sleepObserver))

        tasks.append(
            Task { [sleepObserver, assertions, coordinator, weak self] in
                for await event in await sleepObserver.events() {
                    switch event {
                    case .willSleep:
                        Diagnostics.note("system sleep")
                        await assertions.release()
                    case .didWake:
                        // Every timestamp we hold predates the sleep and is
                        // meaningless now; re-derive from scratch (docs/04).
                        // The watchdog's beat is one of those timestamps.
                        Diagnostics.resetBeat()
                        Diagnostics.note("system wake")
                        await coordinator.resync()
                    }
                    self?.refreshSnapshot()
                }
            }
        )
    }
}

extension BelayController {
    // Beside the other power plumbing for the file-length rule: this is
    // the pipe from the coordinator's decisions to actual assertions.
    func observeDecisions() {
        tasks.append(
            Task { [coordinator, assertions, settings, weak self] in
                for await decision in await coordinator.decisions() {
                    switch decision {
                    case .hold(let reason, let until):
                        let timeout = max(30, until.timeIntervalSinceNow)
                        Diagnostics.note(
                            "hold on reason=\"\(reason)\" "
                                + "display=\(settings.keepDisplayAwake ? 1 : 0)")
                        await assertions.hold(
                            reason: reason,
                            includeDisplay: settings.keepDisplayAwake, timeout: timeout)
                    case .release:
                        Diagnostics.note("hold off")
                        await assertions.release()
                    }
                    self?.refreshSnapshot()
                }
            }
        )
    }
}
