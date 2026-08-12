import BelayCore
import BelaySupport
import Foundation
import Observation

/// Belay's preferences, typed.
///
/// Reads are cheap (the plist is read once at init and clamped); writes persist
/// immediately and notify observers. `policy` is the only thing `BelayCore`
/// needs, which is how the coordinator stays free of UserDefaults.
///
/// The `UserDefaults` instance is injected so tests run against a throwaway
/// suite and can never touch the real user's preferences.
@MainActor
@Observable
public final class SettingsStore {
    /// The app's preferences domain.
    public static let suiteName = "com.perfecto-web.belay"

    /// What init found on disk. The only evidence a migration ran.
    public let migration: SettingsMigrationOutcome

    private var values: SettingsValues {
        didSet { values.write(to: defaults) }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        let outcome = SettingsSchema.migrate(defaults)
        migration = outcome
        // A store written by a newer Belay is unreadable by definition, so we run
        // on defaults rather than guess at its values. Writes still persist, so
        // Settings is not silently read-only.
        values = outcome.usesStoredValues ? SettingsValues(reading: defaults) : .default
    }

    public convenience init(suiteName: String = SettingsStore.suiteName) {
        // `UserDefaults(suiteName:)` returns nil when the name is the app's own
        // bundle identifier — which is exactly what the default is — and macOS
        // logs "does not make sense" every launch. The standard domain *is* that
        // suite, so ask for it directly instead of failing into it.
        guard suiteName != Bundle.main.bundleIdentifier, let suite = UserDefaults(suiteName: suiteName)
        else {
            self.init(defaults: .standard)
            return
        }
        self.init(defaults: suite)
    }

    /// The one value type `BelayCore` consumes. Always in range.
    public var policy: AwakePolicy { values.policy }

    public var mode: AwakeMode {
        get { values.mode }
        set { update { $0.mode = newValue } }
    }

    public var gracePeriod: TimeInterval {
        get { values.gracePeriod }
        set { update { $0.gracePeriod = newValue } }
    }

    /// `nil` means "until turned off" — see `SettingsPresets.maxContinuousAwake`.
    public var maxContinuousAwake: TimeInterval? {
        get { values.maxContinuousAwake }
        set { update { $0.maxContinuousAwake = newValue } }
    }

    public var awaitingUserBudget: TimeInterval {
        get { values.awaitingUserBudget }
        set { update { $0.awaitingUserBudget = newValue } }
    }

    public var sessionTTL: TimeInterval {
        get { values.sessionTTL }
        set { update { $0.sessionTTL = newValue } }
    }

    public var hookFreshnessWindow: TimeInterval {
        get { values.hookFreshnessWindow }
        set { update { $0.hookFreshnessWindow = newValue } }
    }

    /// `nil` disables the battery guard entirely.
    public var batteryFloor: Double? {
        get { values.batteryFloor }
        set { update { $0.batteryFloor = newValue } }
    }

    public var shortenGraceInLowPower: Bool {
        get { values.shortenGraceInLowPower }
        set { update { $0.shortenGraceInLowPower = newValue } }
    }

    public var keepDisplayAwake: Bool {
        get { values.keepDisplayAwake }
        set { update { $0.keepDisplayAwake = newValue } }
    }

    public var assertionTimeout: TimeInterval {
        get { values.assertionTimeout }
        set { update { $0.assertionTimeout = newValue } }
    }

    public var launchAtLogin: Bool {
        get { values.launchAtLogin }
        set { update { $0.launchAtLogin = newValue } }
    }

    public var soundEffects: Bool {
        get { values.soundEffects }
        set { update { $0.soundEffects = newValue } }
    }

    public var hasCompletedOnboarding: Bool {
        get { values.hasCompletedOnboarding }
        set { update { $0.hasCompletedOnboarding = newValue } }
    }

    public var notifyOnAgentNeedsInput: Bool {
        get { values.notifyOnAgentNeedsInput }
        set { update { $0.notifyOnAgentNeedsInput = newValue } }
    }

    public var notifyOnTaskFinished: Bool {
        get { values.notifyOnTaskFinished }
        set { update { $0.notifyOnTaskFinished = newValue } }
    }

    public var notifyOnSafetyRelease: Bool {
        get { values.notifyOnSafetyRelease }
        set { update { $0.notifyOnSafetyRelease = newValue } }
    }

    /// A run shorter than this never earns a "task finished" notification.
    public var taskFinishedThreshold: TimeInterval {
        get { values.taskFinishedThreshold }
        set { update { $0.taskFinishedThreshold = newValue } }
    }

    public var enabledProviders: Set<ProviderID> {
        get { values.enabledProviders }
        set { update { $0.enabledProviders = newValue } }
    }

    public func isEnabled(_ provider: ProviderID) -> Bool {
        values.enabledProviders.contains(provider)
    }

    /// Single write path: clamp, then assign, which persists and notifies.
    /// Clamping before assignment is what keeps a caller's bad number out of
    /// both the plist and the policy.
    private func update(_ change: (inout SettingsValues) -> Void) {
        var next = values
        change(&next)
        values = next.clamped()
    }
}
