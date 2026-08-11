import Foundation
import VigilCore

/// Every key Vigil owns in its preferences domain.
///
/// `CaseIterable` is load-bearing: it is how migration tells a pre-versioned
/// install (has our keys, no schema stamp) from a first launch.
enum SettingsKey: String, CaseIterable {
    case schemaVersion
    case mode
    case gracePeriod
    case maxContinuousAwake
    /// Explicit "until turned off" flag, so unlimited never has to be encoded as
    /// a sentinel number.
    case maxContinuousAwakeUnlimited
    case awaitingUserBudget
    case sessionTTL
    case hookFreshnessWindow
    case batteryFloor
    case batteryGuardEnabled
    case shortenGraceInLowPower
    case keepDisplayAwake
    case assertionTimeout
    case launchAtLogin
    case soundEffects
    case hasCompletedOnboarding
    case notifyOnAgentNeedsInput
    case notifyOnTaskFinished
    case notifyOnSafetyRelease
    case taskFinishedThreshold
    case enabledProviders

    static var settingKeys: [SettingsKey] { allCases.filter { $0 != .schemaVersion } }
}

extension UserDefaults {
    /// `nil` when the key is absent *or* holds something that is not a number.
    /// A corrupt value has to read as "no value" and fall back; reading it as
    /// zero would silently disable a safety cap.
    func number(_ key: SettingsKey) -> Double? {
        guard let value = object(forKey: key.rawValue) as? NSNumber else { return nil }
        return value.doubleValue.isFinite ? value.doubleValue : nil
    }

    func flag(_ key: SettingsKey) -> Bool? {
        guard let value = object(forKey: key.rawValue) as? NSNumber else { return nil }
        return value.boolValue
    }

    func count(_ key: SettingsKey) -> Int? {
        guard let value = object(forKey: key.rawValue) as? NSNumber else { return nil }
        return value.intValue
    }

    func text(_ key: SettingsKey) -> String? { object(forKey: key.rawValue) as? String }

    func strings(_ key: SettingsKey) -> [String]? { object(forKey: key.rawValue) as? [String] }

    func seconds(
        _ key: SettingsKey, in range: ClosedRange<TimeInterval>, or fallback: TimeInterval
    ) -> TimeInterval {
        guard let value = number(key) else { return fallback }
        return range.clamping(value, fallback: fallback)
    }

    func store(_ value: Double, _ key: SettingsKey) { set(value, forKey: key.rawValue) }
    func store(_ value: Bool, _ key: SettingsKey) { set(value, forKey: key.rawValue) }
    func store(_ value: Int, _ key: SettingsKey) { set(value, forKey: key.rawValue) }
    func store(_ value: String, _ key: SettingsKey) { set(value, forKey: key.rawValue) }
    func store(_ value: [String], _ key: SettingsKey) { set(value, forKey: key.rawValue) }

    var holdsAnySetting: Bool {
        SettingsKey.settingKeys.contains { object(forKey: $0.rawValue) != nil }
    }
}

extension SettingsValues {
    /// Reads what is on disk. Absent or corrupt entries fall back to the
    /// default; everything numeric is clamped on the way in.
    init(reading defaults: UserDefaults) {
        let fallback = SettingsValues.default
        self = fallback

        if let raw = defaults.text(.mode), let stored = AwakeMode(rawValue: raw) {
            mode = stored
        }
        gracePeriod = defaults.seconds(
            .gracePeriod, in: SettingsBounds.gracePeriod, or: fallback.gracePeriod)
        maxContinuousAwake = Self.readMaxAwake(defaults, fallback: fallback.maxContinuousAwake)
        awaitingUserBudget = defaults.seconds(
            .awaitingUserBudget, in: SettingsBounds.awaitingUserBudget, or: fallback.awaitingUserBudget)
        sessionTTL = defaults.seconds(.sessionTTL, in: SettingsBounds.sessionTTL, or: fallback.sessionTTL)
        hookFreshnessWindow = defaults.seconds(
            .hookFreshnessWindow, in: SettingsBounds.hookFreshnessWindow, or: fallback.hookFreshnessWindow)
        batteryFloor = Self.readBatteryFloor(defaults, fallback: fallback.batteryFloor)
        shortenGraceInLowPower = defaults.flag(.shortenGraceInLowPower) ?? fallback.shortenGraceInLowPower
        keepDisplayAwake = defaults.flag(.keepDisplayAwake) ?? fallback.keepDisplayAwake
        assertionTimeout = defaults.seconds(
            .assertionTimeout, in: SettingsBounds.assertionTimeout, or: fallback.assertionTimeout)

        launchAtLogin = defaults.flag(.launchAtLogin) ?? fallback.launchAtLogin
        soundEffects = defaults.flag(.soundEffects) ?? fallback.soundEffects
        hasCompletedOnboarding = defaults.flag(.hasCompletedOnboarding) ?? fallback.hasCompletedOnboarding
        notifyOnAgentNeedsInput = defaults.flag(.notifyOnAgentNeedsInput) ?? fallback.notifyOnAgentNeedsInput
        notifyOnTaskFinished = defaults.flag(.notifyOnTaskFinished) ?? fallback.notifyOnTaskFinished
        notifyOnSafetyRelease = defaults.flag(.notifyOnSafetyRelease) ?? fallback.notifyOnSafetyRelease
        taskFinishedThreshold = defaults.seconds(
            .taskFinishedThreshold,
            in: SettingsBounds.taskFinishedThreshold,
            or: fallback.taskFinishedThreshold)
        if let raw = defaults.strings(.enabledProviders) {
            // Unknown identifiers are dropped rather than kept: a provider this
            // build has never heard of cannot be enabled.
            enabledProviders = Set(raw.compactMap(ProviderID.init(rawValue:)))
        }
    }

    func write(to defaults: UserDefaults) {
        defaults.store(mode.rawValue, .mode)
        defaults.store(gracePeriod, .gracePeriod)
        defaults.store(maxContinuousAwake == nil, .maxContinuousAwakeUnlimited)
        // The last finite cap is left behind on purpose, so turning the cap back
        // on restores the number the user chose instead of a default.
        if let maxContinuousAwake { defaults.store(maxContinuousAwake, .maxContinuousAwake) }
        defaults.store(awaitingUserBudget, .awaitingUserBudget)
        defaults.store(sessionTTL, .sessionTTL)
        defaults.store(hookFreshnessWindow, .hookFreshnessWindow)
        defaults.store(batteryFloor != nil, .batteryGuardEnabled)
        if let batteryFloor { defaults.store(batteryFloor, .batteryFloor) }
        defaults.store(shortenGraceInLowPower, .shortenGraceInLowPower)
        defaults.store(keepDisplayAwake, .keepDisplayAwake)
        defaults.store(assertionTimeout, .assertionTimeout)
        defaults.store(launchAtLogin, .launchAtLogin)
        defaults.store(soundEffects, .soundEffects)
        defaults.store(hasCompletedOnboarding, .hasCompletedOnboarding)
        defaults.store(notifyOnAgentNeedsInput, .notifyOnAgentNeedsInput)
        defaults.store(notifyOnTaskFinished, .notifyOnTaskFinished)
        defaults.store(notifyOnSafetyRelease, .notifyOnSafetyRelease)
        defaults.store(taskFinishedThreshold, .taskFinishedThreshold)
        defaults.store(enabledProviders.map(\.rawValue).sorted(), .enabledProviders)
    }

    private static func readMaxAwake(_ defaults: UserDefaults, fallback: TimeInterval?) -> TimeInterval? {
        if defaults.flag(.maxContinuousAwakeUnlimited) == true { return nil }
        guard let stored = defaults.number(.maxContinuousAwake) else { return fallback }
        return SettingsBounds.maxContinuousAwake.clamping(
            stored, fallback: fallback ?? SettingsBounds.maxContinuousAwake.upperBound)
    }

    private static func readBatteryFloor(_ defaults: UserDefaults, fallback: Double?) -> Double? {
        if defaults.flag(.batteryGuardEnabled) == false { return nil }
        guard let stored = defaults.number(.batteryFloor) else { return fallback }
        return SettingsBounds.batteryFloor.clamping(
            stored, fallback: fallback ?? SettingsBounds.batteryFloor.lowerBound)
    }
}
