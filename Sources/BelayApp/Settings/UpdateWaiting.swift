import BelaySupport
import Foundation

/// Whether the app should be saying, unprompted, that an update is waiting.
///
/// Split from `ReleaseChecker` because that file is at the length limit, and
/// because the two answer different questions. The checker answers "what is
/// published"; this answers "should the user be told about it", which is not the
/// same once skipping exists.
///
/// Skipping is per version, not a switch. "I do not want 1.2.1" is a statement
/// about 1.2.1, and reading it as "never tell me about updates" would silently
/// turn off the thing the user only meant to postpone once. When 1.2.2 arrives
/// the mark comes back on its own.
enum UpdateWaiting {
    static let skippedKey = "belay.updates.skippedVersion"

    /// True when there is a published update the user has not skipped.
    static func isWaiting(
        _ status: ReleaseChecker.Status, defaults: UserDefaults = .standard
    ) -> Bool {
        guard case .available(let version, _) = status else { return false }
        return skipped(defaults: defaults) != version
    }

    /// The version this returns is the one the mark stays quiet about.
    static func skipped(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: skippedKey)
    }

    static func skip(_ version: String, defaults: UserDefaults = .standard) {
        Log.app.notice("update skipped at the user's request")
        defaults.set(version, forKey: skippedKey)
    }

    /// Called when an update is installed, so the record does not outlive the
    /// version it was about. Without this, skipping 1.2.1 and then installing it
    /// anyway leaves a stale string in defaults for no reason.
    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: skippedKey)
    }
}
