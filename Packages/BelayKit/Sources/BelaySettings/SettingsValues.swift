import BelayCore
import Foundation

/// Every preference as one value type.
///
/// The store reads this once, clamps it once, and hands `BelayCore` an
/// `AwakePolicy` built from it, so nothing downstream ever reads UserDefaults.
struct SettingsValues: Equatable, Sendable {
    var mode: AwakeMode
    var gracePeriod: TimeInterval
    /// `nil` is "until turned off". Persisted as an explicit unlimited flag, not
    /// as a magic 0.
    var maxContinuousAwake: TimeInterval?
    var awaitingUserBudget: TimeInterval
    var sessionTTL: TimeInterval
    var hookFreshnessWindow: TimeInterval
    /// `nil` disables the battery guard.
    var batteryFloor: Double?
    /// The Always-on timer, so a relaunch does not quietly turn "for two
    /// hours" into "until turned off". Both or neither; the store's accessor
    /// keeps the pair honest.
    var alwaysOnTimerDuration: TimeInterval?
    var alwaysOnTimerDeadline: Date?
    var shortenGraceInLowPower: Bool
    var keepDisplayAwake: Bool
    var assertionTimeout: TimeInterval

    var launchAtLogin: Bool
    var soundEffects: Bool
    var hasCompletedOnboarding: Bool
    /// The version whose release notes this person has already been shown.
    /// `nil` on an install that predates the key.
    var lastSeenVersion: String?
    var notifyOnAgentNeedsInput: Bool
    var notifyOnTaskFinished: Bool
    var notifyOnAgentWentQuiet: Bool
    var notifyOnUpdateAvailable: Bool
    var keepLocalReports: Bool
    var notifyOnSafetyRelease: Bool
    var notifyOnAwaySummary: Bool
    var taskFinishedThreshold: TimeInterval
    var enabledProviders: Set<ProviderID>
    /// Whether the built-in agents have been switched on from what is
    /// actually installed. Done once, on the first launch that can look; the
    /// user's own toggling is never overridden afterwards.
    var builtInsDetected: Bool

    /// Dim the screen at night while holding. Off by default: nobody expects
    /// their utility to touch the display until they ask it to.
    var nightDimming: Bool
    /// Minutes from midnight. The pair may cross it: 22:00 to 07:00.
    var nightDimmingStart: Int
    var nightDimmingEnd: Int
    /// The white point the ramp lands on, 1.0 being untouched. Floored well
    /// above black so a glance at the room still shows the Mac is awake.
    var nightDimmingLevel: Double
    /// Show the Always-on countdown on the dimmed screen, StandBy-style. On
    /// by default: dimming is already opt-in, and the digits are the answer
    /// to the one question a dark held screen raises — "how much longer".
    var nightDimmingShowsTimer: Bool
    /// Hold through a closed lid. Off by default, direct builds only; the
    /// stored choice waits for the privileged helper that does the holding.
    var lidHold: Bool
}

extension SettingsValues {
    /// Derived from `AwakePolicy.default` so the two can never drift apart.
    static let `default` = SettingsValues(policy: .default)

    init(policy: AwakePolicy) {
        mode = policy.mode
        gracePeriod = policy.gracePeriod
        maxContinuousAwake = policy.maxContinuousAwake
        awaitingUserBudget = policy.awaitingUserBudget
        sessionTTL = policy.sessionTTL
        hookFreshnessWindow = policy.hookFreshnessWindow
        batteryFloor = policy.batteryFloor
        shortenGraceInLowPower = policy.shortenGraceInLowPower
        keepDisplayAwake = policy.keepDisplayAwake
        assertionTimeout = policy.assertionTimeout
        launchAtLogin = false
        // On, and quiet enough to stay on. The system's own interface-sound
        // switch still overrides this one.
        soundEffects = true
        hasCompletedOnboarding = false
        lastSeenVersion = nil
        notifyOnAgentNeedsInput = true
        // docs/05: this is the delight moment, so it ships on. Everything else
        // stays conservative because notification fatigue kills utilities.
        notifyOnTaskFinished = true
        notifyOnAgentWentQuiet = true
        notifyOnUpdateAvailable = true
        // Off: nobody asked to be watched, and most people never need this.
        keepLocalReports = false
        notifyOnSafetyRelease = true
        notifyOnAwaySummary = true
        taskFinishedThreshold = 300
        enabledProviders = [.claudeCode]
        builtInsDetected = false
        nightDimming = false
        // Ten in the evening to ten in the morning: wide enough to cover
        // every overnight run and a late start, and both ends are a picker
        // away. Twenty percent: dark, with the frosted veil on top of it,
        // yet a glance at the room still shows the Mac is awake.
        nightDimmingStart = 22 * 60
        nightDimmingEnd = 10 * 60
        nightDimmingLevel = 0.20
        nightDimmingShowsTimer = true
        lidHold = false
    }

    var policy: AwakePolicy {
        AwakePolicy(
            mode: mode,
            gracePeriod: gracePeriod,
            maxContinuousAwake: maxContinuousAwake,
            awaitingUserBudget: awaitingUserBudget,
            sessionTTL: sessionTTL,
            hookFreshnessWindow: hookFreshnessWindow,
            batteryFloor: batteryFloor,
            shortenGraceInLowPower: shortenGraceInLowPower,
            keepDisplayAwake: keepDisplayAwake,
            assertionTimeout: assertionTimeout
        )
    }

    /// Applied after reading the plist and after every write, so no path —
    /// corrupt disk, downgrade, or a caller with a bad number — can persist a
    /// value that breaks an invariant.
    func clamped() -> SettingsValues {
        let fallback = SettingsValues.default
        let defaultMax = fallback.maxContinuousAwake ?? SettingsBounds.maxContinuousAwake.upperBound
        let defaultFloor = fallback.batteryFloor ?? SettingsBounds.batteryFloor.lowerBound
        var copy = self
        copy.gracePeriod = SettingsBounds.gracePeriod.clamping(gracePeriod, fallback: fallback.gracePeriod)
        copy.maxContinuousAwake = maxContinuousAwake.map {
            SettingsBounds.maxContinuousAwake.clamping($0, fallback: defaultMax)
        }
        copy.awaitingUserBudget = SettingsBounds.awaitingUserBudget.clamping(
            awaitingUserBudget, fallback: fallback.awaitingUserBudget)
        copy.sessionTTL = SettingsBounds.sessionTTL.clamping(sessionTTL, fallback: fallback.sessionTTL)
        copy.hookFreshnessWindow = SettingsBounds.hookFreshnessWindow.clamping(
            hookFreshnessWindow, fallback: fallback.hookFreshnessWindow)
        copy.batteryFloor = batteryFloor.map {
            SettingsBounds.batteryFloor.clamping($0, fallback: defaultFloor)
        }
        copy.assertionTimeout = SettingsBounds.assertionTimeout.clamping(
            assertionTimeout, fallback: fallback.assertionTimeout)
        copy.taskFinishedThreshold = SettingsBounds.taskFinishedThreshold.clamping(
            taskFinishedThreshold, fallback: fallback.taskFinishedThreshold)
        copy.nightDimmingStart = SettingsBounds.minuteOfDay.clamping(
            nightDimmingStart, fallback: fallback.nightDimmingStart)
        copy.nightDimmingEnd = SettingsBounds.minuteOfDay.clamping(
            nightDimmingEnd, fallback: fallback.nightDimmingEnd)
        copy.nightDimmingLevel = SettingsBounds.nightDimmingLevel.clamping(
            nightDimmingLevel, fallback: fallback.nightDimmingLevel)
        return copy
    }
}
