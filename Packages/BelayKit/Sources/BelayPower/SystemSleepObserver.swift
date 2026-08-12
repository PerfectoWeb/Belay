import BelaySupport
import Foundation

public enum SystemSleepEvent: Sendable, Equatable {
    case willSleep
    case didWake
}

/// Sleep and wake events, fed in from the app layer.
///
/// `NSWorkspace.willSleepNotification` is posted only on
/// `NSWorkspace.shared.notificationCenter` — not the default centre, not a
/// distributed one — so it cannot be observed without AppKit, and docs/02 says
/// nothing but `BelayApp` imports AppKit. The AppKit-free alternative,
/// `IORegisterForSystemPower`, would oblige BelayPower to own a run loop and to
/// acknowledge every power change with `IOAllowPowerChange`; getting that wrong
/// delays or vetoes system sleep, which is exactly the bug this app must never
/// have. So the app layer observes and calls `report(_:)`, and this type stays
/// a trivially testable relay.
public actor SystemSleepObserver {
    private var subscribers = ContinuationRegistry<SystemSleepEvent>()

    public private(set) var lastEvent: SystemSleepEvent?

    public init() {}

    public func events() -> AsyncStream<SystemSleepEvent> {
        AsyncStream { continuation in
            let token = subscribers.insert(continuation)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(token) }
            }
        }
    }

    /// Called by `BelayApp` from its `NSWorkspace` observers.
    ///
    /// On `.didWake` the coordinator does a full resync: signals that arrived
    /// "during" sleep carry meaningless timestamps (docs/04).
    public func report(_ event: SystemSleepEvent) {
        lastEvent = event
        Log.power.info("System power event: \(String(describing: event), privacy: .public)")
        subscribers.yield(event)
    }

    public func finish() {
        subscribers.finish()
    }

    private func removeSubscriber(_ token: UUID) {
        subscribers.remove(token)
    }
}
