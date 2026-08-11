import Foundation
import IOKit.ps
import VigilSupport

/// What Vigil knows about where the electricity is coming from.
///
/// Deliberately not `PowerConditions` — VigilCore owns policy, this is a reading.
public struct PowerSourceSnapshot: Sendable, Equatable {
    /// True for desktops, which report no internal battery at all.
    public let isOnAC: Bool
    /// 0…1, or `nil` when the machine has no battery.
    public let charge: Double?
    public let isLowPowerMode: Bool

    public init(isOnAC: Bool, charge: Double?, isLowPowerMode: Bool) {
        self.isOnAC = isOnAC
        self.charge = charge
        self.isLowPowerMode = isLowPowerMode
    }
}

/// Polls the power sources on a coalescing timer and publishes changes only.
///
/// A `DispatchSourceTimer` with generous leeway beats
/// `IOPSNotificationCreateRunLoopSource` here: the notification source needs a
/// live run loop and a C callback trampoline, and battery state simply does not
/// move fast enough to be worth either. The floor of 15 s and the 20% leeway
/// keep this inside the idle wakeup budget in docs/08.
public actor PowerSourceMonitor {
    public static let minimumInterval: TimeInterval = 15

    let interval: TimeInterval
    private let queue = DispatchQueue(label: "com.perfecto-web.vigil.powersource", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var subscribers = ContinuationRegistry<PowerSourceSnapshot>()

    var isRunning: Bool { timer != nil }

    public private(set) var current: PowerSourceSnapshot

    public init(interval: TimeInterval = 30) {
        self.interval = max(interval, PowerSourceMonitor.minimumInterval)
        self.current = PowerSourceMonitor.sample()
    }

    /// Emits on change only. Safe to call before or after `start()`.
    public func changes() -> AsyncStream<PowerSourceSnapshot> {
        AsyncStream { continuation in
            let token = subscribers.insert(continuation)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSubscriber(token) }
            }
        }
    }

    public func start() {
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(Int(interval * 200))
        )
        source.setEventHandler { [weak self] in
            Task { await self?.poll() }
        }
        timer = source
        source.resume()
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        subscribers.finish()
    }

    /// Reads the hardware immediately; used on wake, when the poll cadence is
    /// far too slow to be trusted.
    @discardableResult
    public func poll() -> PowerSourceSnapshot {
        let snapshot = PowerSourceMonitor.sample()
        guard snapshot != current else { return snapshot }
        current = snapshot
        subscribers.yield(snapshot)
        return snapshot
    }

    private func removeSubscriber(_ token: UUID) {
        subscribers.remove(token)
    }

    static func sample() -> PowerSourceSnapshot {
        let isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return PowerSourceSnapshot(isOnAC: true, charge: nil, isLowPowerMode: isLowPowerMode)
        }

        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue()
                    as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }

            let state = description[kIOPSPowerSourceStateKey] as? String
            return PowerSourceSnapshot(
                isOnAC: state == kIOPSACPowerValue,
                charge: charge(from: description),
                isLowPowerMode: isLowPowerMode
            )
        }

        // No internal battery means a desktop, which is always on wall power.
        return PowerSourceSnapshot(isOnAC: true, charge: nil, isLowPowerMode: isLowPowerMode)
    }

    private static func charge(from description: [String: Any]) -> Double? {
        guard let capacity = description[kIOPSCurrentCapacityKey] as? Int,
            let maximum = description[kIOPSMaxCapacityKey] as? Int,
            maximum > 0
        else { return nil }
        return min(max(Double(capacity) / Double(maximum), 0), 1)
    }
}
