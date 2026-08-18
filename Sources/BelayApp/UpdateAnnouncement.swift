import BelaySupport
import Foundation

/// Says once, and only once, that a particular version exists.
///
/// The rule the roadmap argued for: never a window that appears by itself, and
/// never a second reminder about a version already mentioned. A person who did
/// not act on "1.2.1 is out" did not miss it; they decided. The next thing they
/// hear about is 1.2.2.
///
/// The version is remembered rather than a flag, so the record cannot drift out
/// of step with what is actually published: a stored "already told them" that
/// does not name a version is a bug waiting for the next release.
enum UpdateAnnouncement {
    static let announcedKey = "belay.updates.announcedVersion"

    /// True when this version has not been announced yet. Records it as a side
    /// effect, because every caller would otherwise have to remember to.
    static func shouldAnnounce(_ version: String, defaults: UserDefaults = .standard) -> Bool {
        guard defaults.string(forKey: announcedKey) != version else { return false }
        defaults.set(version, forKey: announcedKey)
        Log.app.notice("announcing an update once")
        return true
    }
}
