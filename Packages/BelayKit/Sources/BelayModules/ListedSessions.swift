import Foundation

/// A session as an agent's app lists it beside its window.
public struct ListedSession: Equatable, Sendable {
    public enum State: Sendable {
        case idle
        case running
        /// Stopped until somebody answers: a request, or a question.
        case awaiting
        /// The badge says something else: an idle session with a pull
        /// request shows the request's number and state instead of "Idle".
        /// All that matters of it is that the session does not wait.
        case other

        init(mark: String) {
            switch mark {
            case "Idle": self = .idle
            case "Running": self = .running
            case "Awaiting input": self = .awaiting
            default: self = .other
            }
        }
    }

    public let title: String
    public let state: State

    public init(title: String, state: State) {
        self.title = title
        self.state = state
    }

    /// The row says what its badge says and then its title. `mark` is the
    /// badge, and the row has to begin with it: a button in a conversation
    /// may well begin with "Running" and is no session.
    public init?(label: String, mark: String) {
        guard !mark.isEmpty, label.hasPrefix(mark + " ") else { return nil }
        let title = label.dropFirst(mark.count + 1).trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        self.init(title: title, state: State(mark: mark))
    }
}

/// What an app's window is showing.
public enum SessionWindow {
    static let suffix = " - Claude Code"

    /// Claude's page is named after the session it shows.
    public static func shownTitle(from pageTitle: String) -> String? {
        guard pageTitle.hasSuffix(suffix) else { return nil }
        let title = pageTitle.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
    }

    /// Codex names its page after the session and nothing else. A page that
    /// shows no session has a name no row carries, and that is checked where
    /// the rows are.
    public static func codexTitle(from pageTitle: String) -> String? {
        let title = pageTitle.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
    }
}

/// Which waiting session to open next, and which to leave alone.
///
/// A session that was opened and had nothing the rules cover is not opened
/// again while it goes on waiting: it waits for the person, and flipping the
/// window to it every two seconds would help nobody.
public struct SessionVisits: Equatable, Sendable {
    private var declined: Set<String> = []

    public init() {}

    /// The session to open, or nil when there is none. Without knowing what
    /// the window shows there would be no way back, so nothing is opened.
    /// Two sessions by one name cannot be told apart, neither on the way
    /// there nor on the way back.
    public mutating func next(rows: [ListedSession], shown: String?) -> String? {
        notice(rows)
        let isTheOnly = { (title: String) in rows.filter { $0.title == title }.count == 1 }
        guard let shown, isTheOnly(shown) else { return nil }
        return rows.first { row in
            row.state == .awaiting && row.title != shown && !declined.contains(row.title)
                && isTheOnly(row.title)
        }?.title
    }

    /// Takes in the list as it stands: a session that stopped waiting has
    /// moved on, and its next request is a new one. Called on every look and
    /// not only when a visit is possible, or a session that moved on while
    /// the person was at work in the app would stay left alone for good.
    public mutating func notice(_ rows: [ListedSession]) {
        let waiting = Set(rows.filter { $0.state == .awaiting }.map(\.title))
        declined.formIntersection(waiting)
    }

    public mutating func decline(_ title: String) {
        declined.insert(title)
    }
}
