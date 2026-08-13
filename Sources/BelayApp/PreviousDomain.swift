import BelaySettings
import BelaySupport
import Foundation

/// Carries preferences across the one time Belay's bundle identifier changed.
///
/// 1.0.0 shipped as `com.perfecto-web.belay` and everything after it is
/// `com.perfectoweb.belay`, to match the other app on the same developer
/// account. macOS keys preferences by bundle identifier, so without this an
/// update would look to the user like a factory reset: mode, providers,
/// notification choices and the whole usage history, gone with no explanation
/// and no way to get them back.
///
/// The window this matters for is small — eight hours of downloads — but the
/// cost of being wrong about who is in it is somebody's data.
///
/// Deliberately a copy rather than a move. The old domain is left exactly as it
/// was, so someone who goes back to 1.0.0 finds their settings where they left
/// them. Nothing here runs on the App Store build: that identifier never
/// existed there, and a sandboxed app cannot read another app's domain anyway.
enum PreviousDomain {
    static let identifier = "com.perfecto-web.belay"

    /// Set once the copy has happened, so a user who then clears their settings
    /// on purpose does not find them restored at the next launch.
    private static let doneKey = "adoptedPreviousDomain"

    /// Runs before anything reads preferences. Cheap when there is nothing to
    /// do: one boolean read on the common path.
    static func adopt(into destination: UserDefaults = .standard) {
        #if BELAY_MAS
        return
        #else
        guard !destination.bool(forKey: doneKey) else { return }
        destination.set(true, forKey: doneKey)

        guard !destination.holdsAnySetting,
            let carried = UserDefaults.standard.persistentDomain(forName: identifier),
            !carried.isEmpty
        else { return }

        // `persistentDomain(forName:)`, not `dictionaryRepresentation()`. The
        // latter returns the whole resolved hierarchy — every global default
        // macOS has registered, thousands of keys belonging to other people —
        // and the first version of this copied a pile of them into Belay's own
        // domain before the plist was read back and the junk was obvious. The
        // persistent domain is only what was actually written there, which is
        // Belay's settings and the language the user picked.
        for (key, value) in carried {
            destination.set(value, forKey: key)
        }
        Log.settings.notice(
            "Adopted \(carried.count, privacy: .public) settings from the previous bundle identifier")
        #endif
    }
}
