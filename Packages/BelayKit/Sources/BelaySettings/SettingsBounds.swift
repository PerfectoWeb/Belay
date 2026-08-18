import Foundation

/// The range every stored value is squeezed into before anyone sees it.
///
/// Preferences live in a plist the user can edit and a bad migration can
/// corrupt, so nothing read back is trusted. The ceilings exist to protect the
/// safety invariants in docs/00-INVARIANTS.md: an assertion that outlives its refresh, or a
/// session TTL long enough to keep a dead session "alive", both pin the Mac
/// awake with nobody watching.
public enum SettingsBounds {
    /// Below 10 s the hold just flaps; an hour is past any believable "wait for
    /// the agent to come back".
    public static let gracePeriod: ClosedRange<TimeInterval> = 10...3600
    /// A cap under a minute is indistinguishable from off. 24 h is the longest
    /// single hold we are willing to call deliberate; `nil` means unlimited and
    /// bypasses this range entirely.
    public static let maxContinuousAwake: ClosedRange<TimeInterval> = 60...86_400
    /// Waiting on a human is the weakest reason to stay up, so it is capped at
    /// two hours regardless of what is on disk.
    public static let awaitingUserBudget: ClosedRange<TimeInterval> = 60...7200
    /// Invariant 3: a session with no signal for this long is presumed dead. The
    /// ceiling is what stops a corrupt value from resurrecting ghosts forever.
    public static let sessionTTL: ClosedRange<TimeInterval> = 60...7200
    /// How long an exact signal outranks inferred ones. Longer than an hour and
    /// a stale hook event would outvote a live file watcher.
    public static let hookFreshnessWindow: ClosedRange<TimeInterval> = 30...3600
    /// Charge fraction. `nil` disables the guard; anything else is 0…1.
    public static let batteryFloor: ClosedRange<Double> = 0...1
    /// Invariant 2: every assertion self-releases. This is the longest a wedged
    /// or crashed Belay can keep the Mac awake after it stops refreshing.
    public static let assertionTimeout: ClosedRange<TimeInterval> = 30...600
    /// 0 means "tell me about every finished task"; six hours is the far end of
    /// useful for a "that long run is done" notification.
    public static let taskFinishedThreshold: ClosedRange<TimeInterval> = 0...21_600
    /// A clock time, in minutes from midnight.
    public static let minuteOfDay: ClosedRange<Int> = 0...1439
    /// The dimmed white point. The floor is the feature's promise: never so
    /// dark that a glance at the room stops showing the Mac is awake, and a
    /// corrupt plist must not be able to black the screen out.
    public static let nightDimmingLevel: ClosedRange<Double> = 0.10...0.60
}

extension ClosedRange where Bound == Int {
    func clamping(_ value: Bound, fallback: Bound) -> Bound {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}

extension ClosedRange where Bound == Double {
    /// `min`/`max` pass NaN straight through, so a non-finite value from a
    /// corrupt plist is replaced rather than clamped.
    func clamping(_ value: Bound, fallback: Bound) -> Bound {
        guard value.isFinite else { return fallback }
        return Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}
