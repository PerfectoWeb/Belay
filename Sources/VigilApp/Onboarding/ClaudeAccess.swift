import AppKit
import VigilSupport

/// Which `FileAccessProvider` this build reads `~/.claude` through, and the only
/// place that decides.
///
/// The compile condition lives here rather than in VigilKit because it cannot
/// live in VigilKit: `SWIFT_ACTIVE_COMPILATION_CONDITIONS` set on the app target
/// does not reach a local SwiftPM target, so `#if VIGIL_MAS` inside the package
/// is false in every build (`PROJECT_STATE.md` D15). The app makes the choice
/// and injects the result downwards; nothing in detection can tell which it got.
@MainActor
enum ClaudeAccess {
    /// The account's real home, which inside the sandbox is not the container
    /// `FileManager` would hand back. See `UserHome`.
    static let home = UserHome.real

    static var folder: URL { home.appendingPathComponent(".claude", isDirectory: true) }

    #if VIGIL_MAS

    /// One instance for the process: it holds the resolved bookmark, and a
    /// second one would resolve the same grant a second time and open a second
    /// scope for it.
    private static let bookmarked = BookmarkFileAccess.claudeHome(home: home)

    static var provider: FileAccessProvider { bookmarked }

    static var isGranted: Bool { bookmarked.isGranted }

    /// Runs the grant panel and records what the user picked. Returns whether
    /// there is access afterwards, which is not the same as whether they picked
    /// something — a folder that does not contain `~/.claude` grants nothing.
    @discardableResult
    static func request() -> Bool {
        guard let picked = ClaudeFolderPanel.run(startingAt: folder) else { return isGranted }
        do {
            try bookmarked.grant(picked)
        } catch {
            Log.app.error("could not bookmark the folder the user granted: \(error, privacy: .public)")
        }
        return isGranted
    }

    /// Closes the sustained scope on the way out, so the count this process
    /// leaves behind is zero (`docs/06`).
    static func relinquish() { bookmarked.releaseRootScope() }

    #else

    private static let direct = DirectFileAccess()

    static var provider: FileAccessProvider { direct }

    /// Nothing to grant: the direct build reads the folder outright, and
    /// claiming otherwise would put a button in onboarding that does nothing.
    static var isGranted: Bool { true }

    @discardableResult
    static func request() -> Bool { true }

    static func relinquish() {}

    #endif
}
