import BelayProviders
import BelaySupport
import Foundation

/// Persists the user's generic-provider configuration.
///
/// It lives in the app layer rather than in `BelaySettings` because it is a
/// provider's own configuration, and `BelaySettings` models Belay's policy — the
/// values the state machine reads. `GenericTarget` is `Codable`, so this is a
/// blob the store never inspects.
///
/// That "nothing owns where a provider's user settings live" is a real gap in
/// the extensibility contract, not a preference; see PROJECT_STATE D14.
@MainActor
struct GenericTargetStore {
    private let key = "genericTargets"
    private let defaults: UserDefaults

    // `.standard`, not a suite named after the app. `UserDefaults(suiteName:)`
    // returns nil when the name is the app's own bundle identifier, so this
    // took the fallback on every launch and logged "does not make sense" each
    // time. SettingsStore documents the same trap; this is the second copy of
    // that identifier, and the reason there is now none.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [GenericTarget] {
        guard let data = defaults.data(forKey: key) else { return [] }
        do {
            return try JSONDecoder().decode([GenericTarget].self, from: data)
        } catch {
            // A shape change must not wipe detection silently or crash; fall
            // back to none and say so once.
            Log.providers.error("generic targets unreadable, ignoring them: \(error, privacy: .public)")
            return []
        }
    }

    func save(_ targets: [GenericTarget]) {
        do {
            defaults.set(try JSONEncoder().encode(targets), forKey: key)
        } catch {
            Log.providers.error("could not save generic targets: \(error, privacy: .public)")
        }
    }
}
