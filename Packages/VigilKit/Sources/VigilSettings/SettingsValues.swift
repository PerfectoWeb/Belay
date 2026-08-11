import Foundation
import VigilCore

/// Every preference as one value type.
///
/// The store reads this once, clamps it once, and hands `VigilCore` an
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
    var shortenGraceInLowPower: Bool
    var keepDisplayAwake: Bool
    var assertionTimeout: TimeInterval

    var launchAtLogin: Bool
    var hasCompletedOnboarding: Bool
    var notifyOnAgentNeedsInput: Bool
    var notifyOnTaskFinished: Bool
    var notifyOnSafetyRelease: Bool
    var taskFinishedThreshold: TimeInterval
    var enabledProviders: Set<ProviderID>
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
        hasCompletedOnboarding = false
        notifyOnAgentNeedsInput = true
        // docs/05: this is the delight moment, so it ships on. Everything else
        // stays conservative because notification fatigue kills utilities.
        notifyOnTaskFinished = true
        notifyOnSafetyRelease = true
        taskFinishedThreshold = 300
        enabledProviders = [.claudeCode]
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
        return copy
    }
}
