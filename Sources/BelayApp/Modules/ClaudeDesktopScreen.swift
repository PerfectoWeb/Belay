import AppKit
import ApplicationServices
import BelayModules
import os

#if !BELAY_MAS
/// Reads the Claude desktop app through the Accessibility interface.
///
/// A request there is a card: a group marked `epitaxy-approval-card` holding
/// the question, what is asked for, and the two buttons. Read off a running
/// Claude 1.x on 29 September 2026; the class name is theirs and may change,
/// in which case nothing is found and nothing is pressed.
struct ClaudeDesktopScreen: PromptScreen {
    static let bundleIdentifier = "com.anthropic.claudefordesktop"
    static let cardClass = "epitaxy-approval-card"
    static let approveTitle = "Allow once"

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
    /// session into the window can pull Claude to the front, and nobody is to
    /// be pulled out of a sentence. A visit waits for a pause.
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
        read().cards.compactMap(Self.prompt(from:))
    }

    func sessions() -> SessionList {
        list(from: read())
    }

    func survey() -> ScreenSurvey {
        let walk = read()
        return ScreenSurvey(
            pending: walk.cards.compactMap(Self.prompt(from:)), sessions: list(from: walk))
    }

    private func list(from walk: Walk) -> SessionList {
        SessionList(shown: walk.shown, rows: walk.rows.map(\.row)) { title in
            Self.open(title, by: self)
        }
    }

    /// Presses the session's row and waits for the window to follow. The
    /// rows are read afresh: the list is redrawn as sessions change state,
    /// and a row found a moment ago may be gone.
    private static func open(_ title: String, by screen: ClaudeDesktopScreen) -> Bool {
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

    private func read() -> Walk {
        guard isTrusted else { return Walk() }
        let apps = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.bundleIdentifier)
        var windows = 0
        var pages = 0
        let seen = apps.reduce(into: Walk()) { all, app in
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
            var walk = Walk()
            let reachable = element.reachableWindows
            windows += reachable.count
            for window in reachable {
                walk.search(window, depth: 0)
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
            all.cards += walk.cards
            all.rows += walk.rows
            all.shown = all.shown ?? walk.shown
        }
        ClaudeSight.say(
            """
            claude=\(apps.count) windows=\(windows) page=\(pages) \
            session=\(seen.shown == nil ? 0 : 1) list=\(seen.rows.isEmpty ? 0 : 1)
            """)
        return seen
    }

    /// An element is a reference to something in another process, safe to
    /// send anywhere; the type only predates the word for it.
    private struct Row: @unchecked Sendable {
        let row: ListedSession
        let element: AXUIElement
    }

    private struct Walk {
        var visited = 0
        var cards: [AXUIElement] = []
        var rows: [Row] = []
        var shown: String?

        mutating func search(_ element: AXUIElement, depth: Int) {
            visited += 1
            guard depth < ClaudeDesktopScreen.depthLimit, visited < ClaudeDesktopScreen.nodeLimit
            else { return }
            let role = element.string(kAXRoleAttribute)
            if role == kAXGroupRole, element.isCard {
                cards.append(element)
                return
            }
            if role == kAXButtonRole, let row = element.sessionRow {
                rows.append(Row(row: row, element: element))
                return
            }
            if role == "AXWebArea", shown == nil {
                shown = SessionWindow.shownTitle(from: element.label)
            }
            for child in element.elements(kAXChildrenAttribute) {
                search(child, depth: depth + 1)
            }
        }
    }

    private static func prompt(from card: AXUIElement) -> PendingPrompt? {
        var texts: [String] = []
        var button: AXUIElement?
        collect(card, texts: &texts, button: &button, depth: 0)
        guard let button else { return nil }
        let press = Press(card: card, button: button, texts: texts)
        return PendingPrompt(prompt: PermissionPrompt(texts: texts)) { press.perform() }
    }

    /// The words of the card outside its buttons, and the button that says
    /// yes once.
    static func collect(
        _ element: AXUIElement,
        texts: inout [String],
        button: inout AXUIElement?,
        depth: Int
    ) {
        guard depth < 30, texts.count < 200 else { return }
        let role = element.string(kAXRoleAttribute)
        if role == kAXButtonRole {
            let words = element.elements(kAXChildrenAttribute).map { $0.string(kAXValueAttribute) }
            if words.first == approveTitle, button == nil { button = element }
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

    /// An element is a reference to something in another process, safe to
    /// send anywhere; the type only predates the word for it.
    private struct Press: @unchecked Sendable {
        /// A card that has only just appeared takes a press and ignores it.
        /// Measured on 30 September 2026: the first press did nothing in
        /// three seconds, the next one emptied the card in 0.05.
        static let attempts = 10
        static let pause: TimeInterval = 0.4

        let card: AXUIElement
        let button: AXUIElement
        /// What the card said when the rules agreed to it.
        let texts: [String]

        /// Presses until the card goes. Before every press the card is read
        /// again: the page may put the next request into the same place, and
        /// a yes given to one request must never land on another.
        func perform() -> PressOutcome {
            let began = Date()
            for attempt in 0..<Self.attempts {
                guard button.isStillThere else {
                    return attempt == 0
                        ? .gone : .answered(presses: attempt, seconds: Date().timeIntervalSince(began))
                }
                guard saysTheSame else { return .changed }
                guard AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
                else { continue }
                for _ in 0..<4 {
                    Thread.sleep(forTimeInterval: Self.pause / 4)
                    if !button.isStillThere {
                        return .answered(
                            presses: attempt + 1, seconds: Date().timeIntervalSince(began))
                    }
                }
            }
            return .unanswered(presses: Self.attempts)
        }

        private var saysTheSame: Bool {
            var now: [String] = []
            var found: AXUIElement?
            ClaudeDesktopScreen.collect(card, texts: &now, button: &found, depth: 0)
            return now == texts
        }
    }
}
#endif
