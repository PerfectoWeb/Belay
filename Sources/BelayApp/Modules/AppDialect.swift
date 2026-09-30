import ApplicationServices
import BelayModules

#if !BELAY_MAS
/// What the walk through a window came upon.
enum Sighting {
    /// A request's card: the element that holds the whole of it.
    case card(AXUIElement)
    /// A row of the session list, and the element that opens it.
    case row(ListedSession, press: AXUIElement)
}

/// How one app draws the things Belay looks for. The names are the app's own
/// and may change, in which case nothing is found and nothing is pressed.
protocol AppDialect: Sendable {
    var app: AutoAllowRules.App { get }
    var bundleIdentifier: String { get }
    func sighting(at element: AXUIElement, role: String) -> Sighting?
    /// Whether this button of a card says yes to the one request and no more.
    func approvesOnce(_ button: AXUIElement) -> Bool
    /// The session the window shows, from what its page is called.
    func shownTitle(from pageTitle: String) -> String?
    func prompt(in card: AXUIElement, texts: [String]) -> PermissionPrompt
    /// One press of the button, the way this app takes one.
    func press(_ button: AXUIElement, of process: pid_t) -> AXError
}

/// The Claude desktop app. A request is a group marked
/// `epitaxy-approval-card`; read off a running Claude 1.x on 29 September
/// 2026.
struct ClaudeDialect: AppDialect {
    static let cardClass = "epitaxy-approval-card"
    static let approveTitle = "Allow once"

    let app = AutoAllowRules.App.claude
    let bundleIdentifier = "com.anthropic.claudefordesktop"

    func sighting(at element: AXUIElement, role: String) -> Sighting? {
        if role == kAXGroupRole {
            return element.classes.contains(Self.cardClass) ? .card(element) : nil
        }
        guard role == kAXButtonRole, let row = Self.sessionRow(element) else { return nil }
        return .row(row, press: element)
    }

    /// A row of the session list: a button that holds a badge and then a
    /// title, and says both. The badge is drawn; a button in a conversation
    /// that reads the same way holds plain text, and is no session.
    static func sessionRow(_ button: AXUIElement) -> ListedSession? {
        let label = button.label
        guard label.contains(" "), let badge = button.elements(kAXChildrenAttribute).first,
            badge.string(kAXRoleAttribute) != kAXStaticTextRole
        else { return nil }
        return ListedSession(label: label, mark: badge.label)
    }

    func approvesOnce(_ button: AXUIElement) -> Bool {
        let words = button.elements(kAXChildrenAttribute).map { $0.string(kAXValueAttribute) }
        return words.first == Self.approveTitle
    }

    func shownTitle(from pageTitle: String) -> String? {
        SessionWindow.shownTitle(from: pageTitle)
    }

    func prompt(in card: AXUIElement, texts: [String]) -> PermissionPrompt {
        PermissionPrompt(texts: texts)
    }

    func press(_ button: AXUIElement, of process: pid_t) -> AXError {
        AXUIElementPerformAction(button, kAXPressAction as CFString)
    }
}

/// Codex, which lives in the ChatGPT app. A request is a group whose first
/// part is an alert with the question; the page marks the card by a class,
/// but that element does not reach the Accessibility tree. A site the
/// question is about is a link in it. A session is a button inside a handle
/// to drag it by. Read off Codex 26.917 on 30 September 2026.
struct CodexDialect: AppDialect {
    static let rowHandleClass = "cursor-grab"
    static let alertSubrole = "AXApplicationAlert"

    let app = AutoAllowRules.App.codex
    let bundleIdentifier = "com.openai.codex"

    func sighting(at element: AXUIElement, role: String) -> Sighting? {
        guard role == kAXGroupRole else { return nil }
        if element.string(kAXSubroleAttribute) == Self.alertSubrole {
            return element.element(kAXParentAttribute).map { .card($0) }
        }
        guard element.classes.contains(Self.rowHandleClass),
            let button = element.elements(kAXChildrenAttribute).first,
            button.string(kAXRoleAttribute) == kAXButtonRole
        else { return nil }
        let title = button.label
        guard !title.isEmpty else { return nil }
        let mark = button.firstBelow { below in
            below.string(kAXRoleAttribute) == kAXStaticTextRole
                && CodexWords.awaitingApproval.contains(below.string(kAXValueAttribute))
        }
        // The title is whatever the person called the session, the mark's
        // own words included: only a mark that is not the title counts.
        let waits = mark != nil && !CodexWords.awaitingApproval.contains(title)
        return .row(ListedSession(title: title, state: waits ? .awaiting : .other), press: button)
    }

    func approvesOnce(_ button: AXUIElement) -> Bool {
        if CodexWords.allowOnce.contains(button.label) { return true }
        let words = button.firstBelow { $0.string(kAXRoleAttribute) == kAXStaticTextRole }
        return words.map { CodexWords.allowOnce.contains($0.string(kAXValueAttribute)) } ?? false
    }

    func shownTitle(from pageTitle: String) -> String? {
        SessionWindow.codexTitle(from: pageTitle)
    }

    /// The site is the link in the question, and only that: the rest of the
    /// card is the agent's own words.
    func prompt(in card: AXUIElement, texts: [String]) -> PermissionPrompt {
        let alert = card.firstBelow { $0.string(kAXSubroleAttribute) == Self.alertSubrole }
        let link = alert?.firstBelow { $0.string(kAXRoleAttribute) == "AXLink" }
        return PermissionPrompt(texts: texts, site: link?.label ?? "")
    }

    /// Codex takes the click a press sends and does nothing with it, and
    /// answers to the Return key instead (tried on 30 September 2026). The
    /// key goes to the button alone: it is given the focus first, and
    /// nothing is sent while the app says the focus is elsewhere.
    func press(_ button: AXUIElement, of process: pid_t) -> AXError {
        let focusing = AXUIElementSetAttributeValue(button, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        guard focusing == .success else { return focusing }
        guard button.value(kAXFocusedAttribute) as? Bool == true else { return .cannotComplete }
        let returnKey: CGKeyCode = 36
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: returnKey, keyDown: true),
            let up = CGEvent(keyboardEventSource: nil, virtualKey: returnKey, keyDown: false)
        else { return .failure }
        down.postToPid(process)
        up.postToPid(process)
        return .success
    }
}
#endif
