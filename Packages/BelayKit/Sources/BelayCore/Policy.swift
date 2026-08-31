import Foundation

public enum AwakeMode: String, Sendable, CaseIterable, Codable {
    case auto
    case alwaysOn
    case off
}

/// Every tunable the state machine reads. Owned by `BelaySettings` at runtime;
/// declared here so `BelayCore` stays free of the preferences layer.
///
/// The defaults are the product: a user who never opens Settings gets these,
/// and they must be right (docs/05).
public struct AwakePolicy: Sendable, Equatable {
    public var mode: AwakeMode
    /// How long to keep holding after the last session goes idle.
    public var gracePeriod: TimeInterval
    /// Ceiling on one continuous hold. `nil` means unlimited.
    public var maxContinuousAwake: TimeInterval?
    /// How long `awaitingUser` alone may keep the Mac up.
    public var awaitingUserBudget: TimeInterval
    /// A session with no signal for this long is presumed dead.
    public var sessionTTL: TimeInterval
    /// An exact signal outranks inferred ones only while it is this fresh.
    public var hookFreshnessWindow: TimeInterval
    /// Release and refuse to re-arm below this charge while on battery.
    /// `nil` disables the guard.
    public var batteryFloor: Double?
    /// Low Power Mode shortens the grace period rather than stopping work.
    public var shortenGraceInLowPower: Bool
    /// Also prevent display sleep, not just system sleep.
    public var keepDisplayAwake: Bool
    /// Lifetime of each IOKit assertion before it self-releases.
    public var assertionTimeout: TimeInterval

    /// The longest an unclosed tool call may speak for a session.
    ///
    /// Not a setting: nobody should have to know what a tool call is to keep
    /// their Mac awake through a test run. An hour covers the long ones — a
    /// full build, an integration suite — and bounds the one failure this can
    /// have, an agent killed between `PreToolUse` and `PostToolUse`, to an hour
    /// of holding instead of the awake limit's four. See
    /// `SessionState.openToolCallSince`.
    public static let openToolCallBudget: TimeInterval = 60 * 60
    /// How long a Stop's "background tasks still running" claim holds the
    /// session. Shorter than the tool-call budget on purpose: the count can
    /// never be re-verified — no further hook fires while the agent idles —
    /// so this is trust with a timer on it, not evidence.
    public static let backgroundTasksBudget: TimeInterval = 30 * 60

    public static let `default` = AwakePolicy(
        mode: .auto,
        // A round minute, and one of `SettingsPresets.gracePeriods`. It was 90 s,
        // which the pop-up drew as "1 min" because the label rounded: the list
        // and the default agreed on a number nobody could pick.
        gracePeriod: 60,
        maxContinuousAwake: 4 * 60 * 60,
        awaitingUserBudget: 15 * 60,
        sessionTTL: 10 * 60,
        hookFreshnessWindow: 5 * 60,
        batteryFloor: 0.20,
        shortenGraceInLowPower: true,
        keepDisplayAwake: false,
        assertionTimeout: 120
    )

    public init(
        mode: AwakeMode,
        gracePeriod: TimeInterval,
        maxContinuousAwake: TimeInterval?,
        awaitingUserBudget: TimeInterval,
        sessionTTL: TimeInterval,
        hookFreshnessWindow: TimeInterval,
        batteryFloor: Double?,
        shortenGraceInLowPower: Bool,
        keepDisplayAwake: Bool,
        assertionTimeout: TimeInterval
    ) {
        self.mode = mode
        self.gracePeriod = gracePeriod
        self.maxContinuousAwake = maxContinuousAwake
        self.awaitingUserBudget = awaitingUserBudget
        self.sessionTTL = sessionTTL
        self.hookFreshnessWindow = hookFreshnessWindow
        self.batteryFloor = batteryFloor
        self.shortenGraceInLowPower = shortenGraceInLowPower
        self.keepDisplayAwake = keepDisplayAwake
        self.assertionTimeout = assertionTimeout
    }

    /// Grace actually applied, given the current power conditions.
    public func effectiveGrace(lowPower: Bool) -> TimeInterval {
        guard lowPower, shortenGraceInLowPower else { return gracePeriod }
        return max(20, gracePeriod / 3)
    }
}

/// Power conditions the coordinator has to respect. Supplied by `BelayPower`.
public struct PowerConditions: Sendable, Equatable {
    public var isOnAC: Bool
    /// 0…1, or `nil` on a machine with no battery.
    public var charge: Double?
    public var isLowPowerMode: Bool

    public static let unknown = PowerConditions(isOnAC: true, charge: nil, isLowPowerMode: false)

    public init(isOnAC: Bool, charge: Double?, isLowPowerMode: Bool) {
        self.isOnAC = isOnAC
        self.charge = charge
        self.isLowPowerMode = isLowPowerMode
    }

    /// True when we must not hold: on battery, below the floor.
    public func trips(_ floor: Double?) -> Bool {
        guard let floor, !isOnAC, let charge else { return false }
        return charge < floor
    }
}
