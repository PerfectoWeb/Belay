import Foundation

/// Where the bookmark bytes live between launches.
///
/// A protocol so a test can hold them in memory: the real one writes to
/// `UserDefaults`, and a suite that shared the user's defaults would either
/// clobber a real grant or depend on one.
public protocol BookmarkStore: Sendable {
    func data(forKey key: String) -> Data?
    func setData(_ data: Data?, forKey key: String)
}

/// `UserDefaults`, which is what `docs/06` specifies.
///
/// Inside the sandbox that is the app's own container, so the bytes never reach
/// the repository, a shared location, or anywhere a backup would carry them to
/// another Mac — where they would be meaningless anyway.
///
/// `@unchecked Sendable`, justified: the only stored property is a
/// `UserDefaults`, which Foundation documents as thread-safe but does not
/// annotate as `Sendable`. Everything this type adds is two calls that forward
/// straight to it. `SettingsStore` sidesteps the same gap by being `@MainActor`,
/// which is not available here — a bookmark is read from whichever provider
/// actor is doing the reading.
public struct DefaultsBookmarkStore: BookmarkStore, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    public func setData(_ data: Data?, forKey key: String) {
        if let data {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
