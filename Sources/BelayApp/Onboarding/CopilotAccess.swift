import AppKit
import BelaySupport

/// Which `FileAccessProvider` this build reads `~/.copilot` through. The
/// fourth mirror of `ClaudeAccess`, for the reason the second exists: the
/// channel decision cannot live in BelayKit (`docs/PROJECT_STATE.md` D15), so
/// the app makes it and injects the result downwards.
@MainActor
enum CopilotAccess {
    static let home = UserHome.real

    static var folder: URL { home.appendingPathComponent(".copilot", isDirectory: true) }

    #if BELAY_MAS

    private static let bookmarked = BookmarkFileAccess.copilotHome(home: home)

    static var provider: FileAccessProvider { bookmarked }

    static var isGranted: Bool { bookmarked.isGranted }

    @discardableResult
    static func request() -> Bool {
        let picked = ClaudeFolderPanel.run(
            startingAt: folder,
            message: String(
                localized:
                    "Let Belay read your ~/.copilot folder so it can tell when Copilot is working."),
            prompt: String(localized: "Grant access to ~/.copilot"))
        guard let picked else { return isGranted }
        do {
            try bookmarked.grant(picked)
        } catch {
            Log.app.error("could not bookmark the copilot folder: \(error, privacy: .public)")
        }
        return isGranted
    }

    static func relinquish() { bookmarked.releaseRootScope() }

    #else

    private static let direct = DirectFileAccess()

    static var provider: FileAccessProvider { direct }

    static var isGranted: Bool { true }

    @discardableResult
    static func request() -> Bool { true }

    static func relinquish() {}

    #endif
}
