import BelaySupport
import Foundation

/// Which `FileAccessProvider` the generic provider reads its watched folders
/// through, and the only place that decides.
///
/// The sibling of `ClaudeAccess`, and it exists for the same reason: the
/// compile condition cannot live in BelayKit, because
/// `SWIFT_ACTIVE_COMPILATION_CONDITIONS` set on the app target does not reach a
/// local SwiftPM target (`docs/PROJECT_STATE.md` D15). The app decides and injects
/// the result downwards.
///
/// Separate from `ClaudeAccess` because the two grants are different shapes.
/// That one is a bookmark for a single known directory; this is a bookmark for
/// each folder the user picks, wherever it is. Passing the `~/.claude` grant to
/// the generic provider, which is what happened before, meant every folder the
/// user chose was outside it and therefore unreadable.
@MainActor
enum WatchedFolderAccess {
    #if BELAY_MAS

    /// One instance for the process: it holds the resolved bookmarks, and a
    /// second would open a second scope for each of them.
    private static let granted = FolderGrants()

    static var provider: FileAccessProvider { granted }

    /// Records a folder the user just picked in an open panel. Must be called
    /// while the panel's transient scope is still in force, which is why it is
    /// called from the completion handler and not from wherever the target is
    /// saved.
    static func remember(_ url: URL) {
        do {
            try granted.remember(url)
        } catch {
            Log.app.error("could not bookmark a watched folder: \(error, privacy: .public)")
        }
    }

    static func forget(_ url: URL) { granted.forget(url) }

    static func relinquish() { granted.relinquish() }

    #else

    private static let direct = DirectFileAccess()

    static var provider: FileAccessProvider { direct }

    /// Nothing to remember: the direct build reads any folder outright.
    static func remember(_ url: URL) {}

    static func forget(_ url: URL) {}

    static func relinquish() {}

    #endif
}
