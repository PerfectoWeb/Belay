import AppKit
import BelayModules

enum PromptScreens {
    static var forThisChannel: PromptScreen {
        #if BELAY_MAS
        NoScreen()
        #else
        ClaudeDesktopScreen()
        #endif
    }

    static func openSettings() {
        let link = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }
}

/// What came of trying to say yes.
enum PressOutcome: Sendable, Equatable {
    /// The card went after a press of ours.
    case answered(presses: Int, seconds: TimeInterval)
    /// Pressed as often as allowed, and the card is still there.
    case unanswered(presses: Int)
    /// The card went before anything was pressed: the person got there first.
    case gone
    /// The card no longer says what was agreed to, so it was left alone.
    case changed
}

/// A request waiting on the screen, and the way to say yes to it.
struct PendingPrompt: Sendable {
    let prompt: PermissionPrompt
    let approve: @Sendable () -> PressOutcome
}

/// The sessions the app lists beside its window, and the way to bring one
/// into it.
struct SessionList: Sendable {
    /// The session the window shows, when it shows one.
    var shown: String?
    var rows: [ListedSession] = []
    /// True once the window shows the session by that name.
    var open: @Sendable (String) -> Bool = { _ in false }
}

/// Everything one reading of the app gives: the requests and the list.
struct ScreenSurvey: Sendable {
    var pending: [PendingPrompt] = []
    var sessions = SessionList()
}

/// Where permission requests are looked for. Behind a protocol so a test
/// never reads a real window or presses a real button.
protocol PromptScreen: Sendable {
    /// Whether macOS lets Belay read other apps' windows and press in them.
    var isTrusted: Bool { get }
    /// The person is at work on the Mac right now, so the window is not to be
    /// changed under them.
    var isInUse: Bool { get }
    /// Shows the system's own question about that, once.
    func askForTrust()
    /// The requests on the screen right now. Slow: never call it on the main
    /// thread.
    func pending() -> [PendingPrompt]
    /// As slow as `pending`.
    func sessions() -> SessionList
    /// Both from one reading.
    func survey() -> ScreenSurvey
}

extension PromptScreen {
    func survey() -> ScreenSurvey {
        let pending = pending()
        return ScreenSurvey(pending: pending, sessions: sessions())
    }
}

/// What the App Store build has in place of a screen: nothing to read and
/// nothing to press, since the sandbox allows neither.
struct NoScreen: PromptScreen {
    var isTrusted: Bool { false }
    var isInUse: Bool { false }
    func askForTrust() {}
    func pending() -> [PendingPrompt] { [] }
    func sessions() -> SessionList { SessionList() }
}
