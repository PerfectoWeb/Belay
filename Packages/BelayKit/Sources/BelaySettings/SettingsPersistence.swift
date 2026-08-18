import BelayCore
import Foundation

/// Every key Belay owns in its preferences domain.
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
    /// The version whose release notes have been shown. Absent means nobody has
    /// ever been told, which is not the same as "has seen nothing new".
    case lastSeenVersion
    case notifyOnAgentNeedsInput
    case notifyOnTaskFinished
    case notifyOnAgentWentQuiet
    case notifyOnUpdateAvailable
    case keepLocalReports
    case notifyOnSafetyRelease
    case taskFinishedThreshold
    case enabledProviders
    case nightDimming
    case nightDimmingStart
    case nightDimmingEnd
    case nightDimmingLevel

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

    /// Same shape as `seconds`, for stored 0…1 fractions.
    func fraction(
        _ key: SettingsKey, in range: ClosedRange<Double>, or fallback: Double
    ) -> Double {
        guard let value = number(key) else { return fallback }
        return range.clamping(value, fallback: fallback)
    }

    /// Same shape again, for whole numbers such as minutes from midnight.
    func whole(_ key: SettingsKey, in range: ClosedRange<Int>, or fallback: Int) -> Int {
        guard let value = count(key) else { return fallback }
        return range.clamping(value, fallback: fallback)
    }

    func store(_ value: Double, _ key: SettingsKey) { set(value, forKey: key.rawValue) }
    func store(_ value: Bool, _ key: SettingsKey) { set(value, forKey: key.rawValue) }
    func store(_ value: Int, _ key: SettingsKey) { set(value, forKey: key.rawValue) }
    func store(_ value: String, _ key: SettingsKey) { set(value, forKey: key.rawValue) }
    func store(_ value: [String], _ key: SettingsKey) { set(value, forKey: key.rawValue) }

    /// Whether Belay has ever written a setting here. Public because the app
    /// target asks it of a *different* domain: see `PreviousDomain`.
    public var holdsAnySetting: Bool {
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
        // No fallback on purpose. `nil` is a state the caller has to handle:
        // an install that predates this key is not a new install.
        lastSeenVersion = defaults.text(.lastSeenVersion)
        notifyOnAgentNeedsInput = defaults.flag(.notifyOnAgentNeedsInput) ?? fallback.notifyOnAgentNeedsInput
        notifyOnTaskFinished = defaults.flag(.notifyOnTaskFinished) ?? fallback.notifyOnTaskFinished
        notifyOnAgentWentQuiet =
            defaults.flag(.notifyOnAgentWentQuiet) ?? fallback.notifyOnAgentWentQuiet
        notifyOnUpdateAvailable =
            defaults.flag(.notifyOnUpdateAvailable) ?? fallback.notifyOnUpdateAvailable
        keepLocalReports = defaults.flag(.keepLocalReports) ?? fallback.keepLocalReports
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
        nightDimming = defaults.flag(.nightDimming) ?? fallback.nightDimming
        nightDimmingStart = defaults.whole(
            .nightDimmingStart, in: SettingsBounds.minuteOfDay, or: fallback.nightDimmingStart)
        nightDimmingEnd = defaults.whole(
            .nightDimmingEnd, in: SettingsBounds.minuteOfDay, or: fallback.nightDimmingEnd)
        nightDimmingLevel = defaults.fraction(
            .nightDimmingLevel, in: SettingsBounds.nightDimmingLevel, or: fallback.nightDimmingLevel)
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
        // Written only when there is one, so "never told" stays distinguishable
        // from "told about nothing".
        if let lastSeenVersion { defaults.store(lastSeenVersion, .lastSeenVersion) }
        defaults.store(notifyOnAgentNeedsInput, .notifyOnAgentNeedsInput)
        defaults.store(notifyOnTaskFinished, .notifyOnTaskFinished)
        defaults.store(notifyOnAgentWentQuiet, .notifyOnAgentWentQuiet)
        defaults.store(notifyOnUpdateAvailable, .notifyOnUpdateAvailable)
        defaults.store(keepLocalReports, .keepLocalReports)
        defaults.store(notifyOnSafetyRelease, .notifyOnSafetyRelease)
        defaults.store(taskFinishedThreshold, .taskFinishedThreshold)
        defaults.store(enabledProviders.map(\.rawValue).sorted(), .enabledProviders)
        defaults.store(nightDimming, .nightDimming)
        defaults.store(nightDimmingStart, .nightDimmingStart)
        defaults.store(nightDimmingEnd, .nightDimmingEnd)
        defaults.store(nightDimmingLevel, .nightDimmingLevel)
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
