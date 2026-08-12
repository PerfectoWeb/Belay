import AppKit
import BelayPower

/// Bridges `NSWorkspace`'s sleep and wake notifications into the observer
/// BelayPower owns.
///
/// Split out of `BelayController` only to keep that file under the length rule,
/// the same way `ClaudeCodeAvailability` is split out of its provider. The
/// reason it has to exist at all: those notifications are delivered on
/// `NSWorkspace`'s own notification centre, which BelayPower deliberately
/// cannot reach, so the app layer forwards them in.
@MainActor
enum SleepWakeForwarding {
    /// Returns the observer tokens; the caller removes them on teardown.
    static func install(into observer: SystemSleepObserver) -> [NSObjectProtocol] {
        let events: [(Notification.Name, SystemSleepEvent)] = [
            (NSWorkspace.willSleepNotification, .willSleep),
            (NSWorkspace.didWakeNotification, .didWake)
        ]
        return events.map { name, event in
            NSWorkspace.shared.notificationCenter
                .addObserver(forName: name, object: nil, queue: .main) { _ in
                    Task { await observer.report(event) }
                }
        }
    }
}
