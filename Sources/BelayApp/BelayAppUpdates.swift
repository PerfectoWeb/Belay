import BelaySettings
import Foundation

/// Everything the app does about update checks: when one runs, and what happens
/// when the answer changes.
///
/// Split from `BelayApp.swift`, which is at the length limit. This is one
/// subject and it reads better in one place than threaded through app setup.
extension AppDelegate {
    /// Daily, and once shortly after launch.
    ///
    /// The post-launch one waits for onboarding to have been through at least
    /// once. Checks are on by default now, and without this the very first
    /// launch opened a socket eight seconds in, while the welcome screen was
    /// still on the display saying nothing leaves this Mac. Both statements were
    /// true separately and the pair of them was not.
    /// Redraws the mark when the checker's answer changes.
    ///
    /// Not when the question is asked. `checkIfDue` starts a network task and
    /// returns immediately, so rendering on the line after it renders the answer
    /// from before the check. The status is `@Observable`, so the change itself is
    /// the event, and re-arming inside the handler is what makes it more than a
    /// one-shot.
    func observeUpdateStatus(_ checker: ReleaseChecker) {
        withObservationTracking {
            _ = checker.status
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.statusItem?.render()
                if case .available(let version, _) = checker.status {
                    await self?.controller?.announceUpdate(version: version)
                }
                self?.observeUpdateStatus(checker)
            }
        }
    }

    func scheduleUpdateChecks(_ checker: ReleaseChecker) {
        let timer = Timer(timeInterval: 3600, repeats: true) { _ in
            MainActor.assumeIsolated { checker.checkIfDue() }
        }
        timer.tolerance = 600
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
        // After launch, not during it: nothing about an update belongs in the
        // cold-start path.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard self?.settings.hasCompletedOnboarding == true else { return }
            checker.checkIfDue()
        }
    }
}
