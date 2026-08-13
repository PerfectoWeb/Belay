import AppKit
import BelaySupport

/// Makes sure only one Belay is ever running.
///
/// Two copies is not a cosmetic problem here: each one runs its own detection,
/// each takes its own IOKit assertion, and `docs/00-INVARIANTS.md` invariant 1 — at most one
/// assertion process-wide — quietly stops being true of the machine. It also
/// makes the app impossible to reason about, which is how a stale build spent an
/// hour answering accessibility queries meant for a fresh one.
enum SingleInstance {
    /// Returns false when another copy already owns the menu bar, after handing
    /// that copy the foreground so the user sees *something* happen.
    static func claim() -> Bool {
        // The XCTest host is itself a Belay, so with a real one running the
        // guard terminated the test runner before it could connect and every
        // app-level test failed with "early unexpected exit".
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return true
        }
        let identifier = Branding.bundleIdentifier
        let mine = ProcessInfo.processInfo.processIdentifier

        let others = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .filter { $0.processIdentifier != mine && !$0.isTerminated }

        guard let existing = others.first else { return true }

        Log.app.notice("another Belay is already running; deferring to it")
        // Without this the second launch just vanishes and looks like a crash.
        existing.activate(options: [])
        return false
    }
}
