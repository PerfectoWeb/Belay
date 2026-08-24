import AppKit
import BelayCore
import BelaySupport

/// The Always-on timer's wiring, and the human-returned signal that re-arms a
/// tripped cap. Beside `BelayController` for the same dull length reason as
/// the power observers.
extension BelayController {
    func setAlwaysOnTimer(_ duration: TimeInterval?) {
        Diagnostics.note(duration.map { "timer set \(Int($0))s" } ?? "timer off")
        settings.alwaysOnTimer = duration.map { ($0, Date().addingTimeInterval($0)) }
        Task { [coordinator, driver, weak self] in
            await coordinator.setAlwaysOnTimer(duration)
            await driver.nudge()
            self?.refreshSnapshot()
        }
    }

    /// Puts a persisted timer back after a relaunch — or clears the record
    /// when the mode moved on while it sat there.
    func restoreAlwaysOnTimer() {
        guard let stored = settings.alwaysOnTimer else { return }
        guard settings.mode == .alwaysOn else {
            settings.alwaysOnTimer = nil
            return
        }
        let left = Int(stored.deadline.timeIntervalSinceNow)
        Diagnostics.note("timer restored \(Int(stored.duration))s deadline in \(left)s")
        Task { [coordinator, driver, weak self] in
            await coordinator.restoreAlwaysOnTimer(
                duration: stored.duration, deadline: stored.deadline)
            await driver.nudge()
            self?.refreshSnapshot()
        }
    }

    /// The pause's one-click exit, from the panel's "Hold again" button.
    func holdAgain() {
        Diagnostics.note("hold again")
        // The re-armed timer's fresh deadline must outlive a relaunch too.
        if let stored = settings.alwaysOnTimer {
            settings.alwaysOnTimer = (stored.duration, Date().addingTimeInterval(stored.duration))
        }
        Task { [coordinator, driver, weak self] in
            await coordinator.holdAgain()
            await driver.nudge()
            self?.refreshSnapshot()
        }
    }

    /// Screen wake and unlock both mean a human is back at the machine, which
    /// is the cap's cue to start a fresh cycle — the same sanction a wake from
    /// sleep already gives through `resync`. The timer is deliberately not
    /// renewed here; see `ActivityCoordinator.renewCapOnReturn`.
    func observeHumanReturn() {
        sleepObservers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.renewCapOnReturn() }
            }
        )
        // Unlock arrives on the distributed centre, not NSWorkspace's, so its
        // token cannot ride in `sleepObservers`: removal has to name the same
        // centre that registered it.
        unlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.renewCapOnReturn() }
        }
    }

    private func renewCapOnReturn() {
        Task { [coordinator, driver, weak self] in
            await coordinator.renewCapOnReturn()
            await driver.nudge()
            self?.refreshSnapshot()
        }
    }
}
