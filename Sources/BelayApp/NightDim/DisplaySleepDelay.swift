import BelaySupport
import Foundation

/// The system's own display-sleep delay: the moment that would have darkened
/// the screen if Belay had not held it awake. Dimming keys off it so the
/// feature mimics what the machine was already going to do (docs/ROADMAP).
///
/// The number lives in the power-management preferences, which only
/// `IOPMCopyActivePMPreferences` reads — a private symbol. The direct build
/// resolves it at runtime and falls back when it is missing; the sandboxed
/// build never references it (guideline 2.5.1) and lives on the fallback,
/// which is the macOS default of ten minutes.
enum DisplaySleepDelay {
    /// What macOS ships with when nobody has touched Battery settings.
    static let fallback: TimeInterval = 600

    /// `nil` means the system would never sleep this display — the lit screen
    /// is the user's own arrangement, so it is not Belay's to darken.
    static func current(onAC: Bool) -> TimeInterval? {
        guard let minutes = preferredMinutes(onAC: onAC) else { return fallback }
        guard minutes > 0 else { return nil }
        return minutes * 60
    }

    #if BELAY_MAS
    private static func preferredMinutes(onAC: Bool) -> Double? { nil }
    #else
    private typealias CopyPreferences = @convention(c) () -> Unmanaged<CFDictionary>?

    /// Resolved once. `nil` when the symbol is gone — a future macOS is
    /// allowed to take it away and the fallback must be the only casualty.
    private static let copyPreferences: CopyPreferences? = {
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "IOPMCopyActivePMPreferences") else {
            Log.app.notice(
                "IOPMCopyActivePMPreferences unavailable; night dimming uses the default delay")
            return nil
        }
        return unsafeBitCast(symbol, to: CopyPreferences.self)
    }()

    private static func preferredMinutes(onAC: Bool) -> Double? {
        guard let copyPreferences,
            let preferences = copyPreferences()?.takeRetainedValue() as? [String: [String: Any]]
        else { return nil }
        let source = onAC ? "AC Power" : "Battery Power"
        guard let value = preferences[source]?["Display Sleep Timer"] as? NSNumber else {
            return nil
        }
        return value.doubleValue
    }
    #endif
}
