import AppKit
import BelaySupport
import Foundation

/// The interface language, and the one honest way to change it at runtime.
///
/// There is no separate stored preference: macOS already has one. `AppleLanguages`
/// in the app's own defaults domain is what `Bundle.main` consults when it picks
/// a `.lproj` at launch, so writing anything else would mean keeping two sources
/// of truth in step, and the one the system reads would win anyway.
///
/// Switching therefore needs a relaunch. SwiftUI could be coerced into re-reading
/// with a locale environment override, but the menu bar menu, the quit
/// confirmation and every `NSAlert` are AppKit and would keep the old language —
/// a half-translated app is worse than one that asks you to reopen it. System
/// Settings' own per-app language control says the same thing and offers the
/// same button.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case russian = "ru"
    case german = "de"
    case spanish = "es"
    case french = "fr"
    case italian = "it"

    var id: String { rawValue }

    /// Written in the language itself. A picker that lists "German" to somebody
    /// who only reads German is a picker they cannot use.
    ///
    /// "System" is the exception and is translated: it names a behaviour, not a
    /// language, and left in English it was the one Latin word at the top of a
    /// Cyrillic list.
    var endonym: String {
        switch self {
        case .system: return String(localized: "System")
        case .english: return "English"
        case .russian: return "Русский"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        case .french: return "Français"
        case .italian: return "Italiano"
        }
    }

    /// Every language the bundle actually ships, in menu order.
    static var offered: [AppLanguage] { allCases }

    static let defaultsKey = "AppleLanguages"

    /// What the user has chosen, which is not the same as what is on screen: an
    /// unsupported system language shows English while this still reads `.system`.
    static func selected(in defaults: UserDefaults = .standard) -> AppLanguage {
        guard let first = defaults.stringArray(forKey: defaultsKey)?.first else { return .system }
        return allCases.first { $0 != .system && $0.rawValue == first } ?? .system
    }

    /// Records the choice. Takes effect on the next launch, by design.
    static func select(_ language: AppLanguage, in defaults: UserDefaults = .standard) {
        if language == .system {
            defaults.removeObject(forKey: defaultsKey)
        } else {
            defaults.set([language.rawValue], forKey: defaultsKey)
        }
        Log.app.notice("interface language set to \(language.rawValue, privacy: .public)")
    }

    /// Whether a restart would actually change anything on screen. Choosing
    /// "System" on a Russian Mac while already running in Russian should not
    /// nag the user to relaunch for nothing.
    static func needsRelaunch(
        for language: AppLanguage,
        running: String? = Bundle.main.preferredLocalizations.first
    ) -> Bool {
        guard let running else { return language != .system }
        return resolved(language).map { $0 != running } ?? false
    }

    /// The localisation the bundle would pick for a choice, or nil when only the
    /// system can answer.
    private static func resolved(_ language: AppLanguage) -> String? {
        guard language != .system else {
            return Bundle.preferredLocalizations(
                from: Bundle.main.localizations, forPreferences: Locale.preferredLanguages
            ).first ?? "en"
        }
        return language.rawValue
    }
}

@MainActor
enum Relaunch {
    /// Whether this build can bring itself back.
    ///
    /// The App Store build is sandboxed with no exceptions, so the helper below
    /// runs inside the container and a LaunchServices launch from there is at
    /// best unverified. Quitting on the promise of a relaunch that may never
    /// come would make the language picker uninstall the app from the user's
    /// session — so on that channel Belay says what to do instead of guessing.
    static var isAvailable: Bool {
        #if BELAY_MAS
        return false
        #else
        return true
        #endif
    }

    /// Quit, then come back.
    ///
    /// The new copy is started by a detached `sh` that waits for this process to
    /// be gone, because `SingleInstance` refuses a second Belay — launching
    /// first and quitting second would have the replacement defer to the copy on
    /// its way out, and the app would simply disappear.
    ///
    /// Two hardenings, both for silent failures found in review. `kill -0` stops
    /// answering the instant the kernel drops the process entry, but
    /// LaunchServices learns of the death later; opening into that gap either
    /// activates a dead registration or starts a copy that `SingleInstance`
    /// then terminates. Hence the settle. And `open` is retried, because
    /// `try task.run()` succeeding only proves `sh` started — the app is already
    /// terminating by the time `open` can fail, so nothing is left to report it.
    static func now(bundle: URL = Bundle.main.bundleURL) {
        guard isAvailable else { return }
        let path = bundle.path.shellQuoted
        let script = """
            while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do
              /bin/sleep 0.2
            done
            /bin/sleep 0.8
            for attempt in 1 2 3; do
              /usr/bin/open \(path) && exit 0
              /bin/sleep 1
            done
            """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script]
        do {
            try task.run()
        } catch {
            Log.app.error("relaunch failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        NSApp.terminate(nil)
    }
}

extension String {
    /// Single quotes, with any embedded quote closed and reopened — the app can
    /// live at a path with spaces in it, and this one does.
    var shellQuoted: String { "'" + replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
