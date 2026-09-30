import AppKit
import ApplicationServices
import BelayModules
import os

#if !BELAY_MAS
/// Reads an agent's desktop app through the Accessibility interface.
///
/// A request there is a card: a group holding the question, what is asked
/// for, and the buttons. Which group, which button and which rows is what the
/// dialect knows; the looking and the pressing are the same for every app.
struct AppScreen: PromptScreen {
    let dialect: any AppDialect

    /// A page is a few thousand elements. Past this something is wrong, and a
    /// walk that never ends would hold a thread for good.
    static let nodeLimit = 20_000
    static let depthLimit = 90
    /// A window without its page is a few dozen elements of frame.
    static let emptyPage = 200

    private static let introduced = OSAllocatedUnfairLock(initialState: Set<pid_t>())

    /// Somebody who touched the Mac this recently is still at it.
    static let recentInput: TimeInterval = 5
    /// How long a session may take to come into the window.
    static let openingLimit: TimeInterval = 3

    var isTrusted: Bool { AXIsProcessTrusted() }

    /// Typing, clicking or moving the pointer, in whatever app: bringing a
    /// session into the window can pull the app to the front, and nobody is
    /// to be pulled out of a sentence. A visit waits for a pause.
    var isInUse: Bool {
        guard let anyInput = CGEventType(rawValue: ~0) else { return false }
        let quiet = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState, eventType: anyInput)
        return quiet < Self.recentInput
    }

    func askForTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func pending() -> [PendingPrompt] {
        read().cards.compactMap(prompt(from:))
    }

    func sessions() -> SessionList {
        list(from: read())
    }

    func survey() -> ScreenSurvey {
        let walk = read()
        return ScreenSurvey(
            pending: walk.cards.compactMap(prompt(from:)), sessions: list(from: walk))
    }

    private func list(from walk: Seen) -> SessionList {
        SessionList(shown: walk.shown, rows: walk.rows.map(\.row)) { title in
            Self.open(title, by: self)
        }
    }

    /// Presses the session's row and waits for the window to follow. The
    /// rows are read afresh: the list is redrawn as sessions change state,
    /// and a row found a moment ago may be gone.
    private static func open(_ title: String, by screen: AppScreen) -> Bool {
        let began = Date()
        while Date().timeIntervalSince(began) < openingLimit {
            let walk = screen.read()
            if walk.shown == title { return true }
            guard let row = walk.rows.first(where: { $0.row.title == title }) else { return false }
            AXUIElementPerformAction(row.element, kAXPressAction as CFString)
            Thread.sleep(forTimeInterval: 0.3)
        }
        return screen.read().shown == title
    }

    private func read() -> Seen {
        guard isTrusted else { return Seen() }
        let apps = NSRunningApplication.runningApplications(
            withBundleIdentifier: dialect.bundleIdentifier)
        var windows = 0
        var pages = 0
        let seen = apps.reduce(into: Seen()) { all, app in
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 1)
            let process = app.processIdentifier
            // Chromium builds its accessibility tree only for somebody who
            // says they are reading it. Said once per process: Claude writes
            // a line to its log every time it hears it, and the value cannot
            // be read back.
            if !Self.introduced.withLock({ $0.contains(process) }) {
                AXUIElementSetAttributeValue(
                    element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            }
            var walk = Walk(dialect: dialect)
            let reachable = element.reachableWindows
            windows += reachable.count
            for window in reachable {
                walk.search(window, depth: 0, inPage: false)
            }
            // A walk this short saw the window and no page in it, so the tree
            // is not there and the next look says it again.
            let sawThePage = walk.visited >= Self.emptyPage
            if sawThePage { pages += 1 }
            Self.introduced.withLock {
                if sawThePage {
                    $0.insert(process)
                } else {
                    $0.remove(process)
                }
            }
            all.cards += walk.cards.map { Card(element: $0, process: process) }
            all.rows += walk.rows
            all.shown = all.shown ?? walk.shown
        }
        AppSight.say(
            """
            \(dialect.app.rawValue)=\(apps.count) windows=\(windows) page=\(pages) \
            session=\(seen.shown == nil ? 0 : 1) list=\(seen.rows.isEmpty ? 0 : 1)
            """, of: dialect.app)
        return seen
    }

    /// An element is a reference to something in another process, safe to
    /// send anywhere; the type only predates the word for it.
    fileprivate struct Row: @unchecked Sendable {
        let row: ListedSession
        let element: AXUIElement
    }

    struct Card: @unchecked Sendable {
        let element: AXUIElement
        let process: pid_t
    }

    /// What every window of the app together showed.
    struct Seen {
        var cards: [Card] = []
        fileprivate var rows: [Row] = []
        var shown: String?
    }

    private struct Walk {
        let dialect: any AppDialect
        var visited = 0
        var cards: [AXUIElement] = []
        var rows: [Row] = []
        var shown: String?

        mutating func search(_ element: AXUIElement, depth: Int, inPage: Bool) {
            visited += 1
            guard depth < AppScreen.depthLimit, visited < AppScreen.nodeLimit else { return }
            let role = element.string(kAXRoleAttribute)
            let isPage = role == "AXWebArea"
            // A page shown inside the app's own page is somebody else's:
            // whatever it draws, a card of the app's it is not.
            if isPage, inPage { return }
            switch dialect.sighting(at: element, role: role) {
            case .card(let card):
                cards.append(card)
                return
            case .row(let row, let press):
                rows.append(Row(row: row, element: press))
                return
            case nil:
                break
            }
            if isPage, shown == nil { shown = dialect.shownTitle(from: element.label) }
            for child in element.elements(kAXChildrenAttribute) {
                search(child, depth: depth + 1, inPage: inPage || isPage)
            }
        }
    }

    private func prompt(from card: Card) -> PendingPrompt? {
        var texts: [String] = []
        var button: AXUIElement?
        collect(card.element, texts: &texts, button: &button, depth: 0)
        guard let button else { return nil }
        let press = AppPress(screen: self, card: card, button: button, texts: texts)
        return PendingPrompt(prompt: dialect.prompt(in: card.element, texts: texts)) { press.perform() }
    }

    /// The words of the card outside its buttons, and the button that says
    /// yes once.
    func collect(
        _ element: AXUIElement,
        texts: inout [String],
        button: inout AXUIElement?,
        depth: Int
    ) {
        guard depth < 30, texts.count < 200 else { return }
        let role = element.string(kAXRoleAttribute)
        if role == kAXButtonRole {
            if button == nil, dialect.approvesOnce(element) { button = element }
            return
        }
        if role == kAXStaticTextRole {
            let text = element.string(kAXValueAttribute)
            if !text.isEmpty { texts.append(text) }
            return
        }
        for child in element.elements(kAXChildrenAttribute) {
            collect(child, texts: &texts, button: &button, depth: depth + 1)
        }
    }
}
#endif
