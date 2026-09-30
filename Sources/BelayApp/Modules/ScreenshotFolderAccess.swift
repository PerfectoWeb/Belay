import BelaySupport
import Foundation

/// How the screenshot cleaner reaches its folders, and the only place that
/// decides. The sibling of `WatchedFolderAccess`, for the same reason: the
/// compile condition does not reach BelayKit, so the app picks and injects.
enum ScreenshotFolderAccess {
    #if BELAY_MAS

    /// The sandbox cannot read another app's preferences, so the capture
    /// folder is not something this build can look up. The user points at it.
    static let asksForFolder = true

    /// Its own grants, under its own keys: removing the module must not take a
    /// watched tool's folder with it, and the other way round.
    private static let granted = FolderGrants(
        store: PrefixedBookmarkStore(prefix: "BelayScreenshots."))

    static var provider: FileAccessProvider { granted }

    /// Must run while the open panel's transient scope is still in force.
    static func remember(_ url: URL) -> Bool {
        do {
            try granted.remember(url)
            return true
        } catch {
            Log.app.error("could not bookmark a screenshot folder: \(error, privacy: .public)")
            return false
        }
    }

    static func forget(_ url: URL) { granted.forget(url) }

    static func relinquish() { granted.relinquish() }

    #else

    static let asksForFolder = false

    static var provider: FileAccessProvider { DirectFileAccess() }

    static func remember(_ url: URL) -> Bool { true }

    static func forget(_ url: URL) {}

    static func relinquish() {}

    #endif

    /// Where macOS saves captures. The Desktop unless the user moved it in the
    /// Screenshot app's options, which only the direct build can see.
    static var systemFolder: URL {
        let desktop = UserHome.real.appending(path: "Desktop", directoryHint: .isDirectory)
        guard !asksForFolder,
            let raw = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
            !raw.isEmpty
        else { return desktop }
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
    }
}

/// A bookmark store that keeps its keys apart from everyone else's.
struct PrefixedBookmarkStore: BookmarkStore {
    let prefix: String
    var base: BookmarkStore = DefaultsBookmarkStore()

    func data(forKey key: String) -> Data? {
        base.data(forKey: prefix + key)
    }

    func setData(_ data: Data?, forKey key: String) {
        base.setData(data, forKey: prefix + key)
    }
}
