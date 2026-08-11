import CoreGraphics
import Foundation

/// How long the user has been away from the keyboard.
///
/// This is what makes the statistics honest. "Vigil held your Mac awake for
/// 12 hours" is not a claim about value — the Mac was not going to sleep while
/// you were typing anyway. **Time held while you were away** is the thing that
/// would otherwise have ended in a dead run, and it needs no permission and no
/// guess about the user's sleep settings to measure.
///
/// The alternative was reading the system's idle-sleep timer to decide whether a
/// hold "would have" been interrupted. `IOPMCopyPMPreferences` is not exposed to
/// Swift, the IORegistry does not publish the timer, and the preferences plist
/// is not readable under sandbox — so that number would have been a guess
/// dressed up as a measurement.
enum AwayTime {
    /// Below this the user is at the machine and nothing was at risk.
    static let threshold: TimeInterval = 5 * 60

    static func secondsSinceInput() -> TimeInterval {
        guard let anyEvent = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyEvent)
    }

    static func isAway(_ idle: TimeInterval = secondsSinceInput()) -> Bool {
        idle >= threshold
    }
}
