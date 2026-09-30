import BelayModules
import Foundation

@testable import Belay

/// A microphone that is only a count of how often it was opened and closed.
final class FakeTap: MicTap, @unchecked Sendable {
    private let lock = NSLock()
    private var name: String?
    private var handler: (@Sendable () -> Void)?
    private var openCount = 0
    private var closeCount = 0

    init(name: String? = "Test Microphone") {
        self.name = name
    }

    var opens: Int { lock.withLock { openCount } }
    var closes: Int { lock.withLock { closeCount } }

    func plug(_ name: String?) { lock.withLock { self.name = name } }

    func open(_ opened: @escaping @Sendable (String?) -> Void) {
        let name = lock.withLock {
            openCount += 1
            return self.name
        }
        opened(name)
    }

    func close() { lock.withLock { closeCount += 1 } }

    func whenDisturbed(_ handler: @escaping @Sendable () -> Void) {
        lock.withLock { self.handler = handler }
    }

    func disturb() { lock.withLock { handler }?() }
}

/// The Mac around the microphone, as a test wants it.
@MainActor
final class FakeMac {
    var permission: MicPermission = .granted
    /// What the user answers when asked.
    var answer = true
    var isOnBattery = false
    var input: MicKind? = .builtIn
    private(set) var asked = 0
    private var watchers: [UUID: @MainActor () -> Void] = [:]

    var watching: Int { watchers.count }

    func change() { watchers.values.forEach { $0() } }

    var surroundings: MicSurroundings {
        MicSurroundings(
            permission: { self.permission },
            ask: { answered in
                self.asked += 1
                self.permission = self.answer ? .granted : .refused
                answered(self.answer)
            },
            isOnBattery: { self.isOnBattery },
            inputKind: { self.input },
            watch: { changed in
                let id = UUID()
                self.watchers[id] = changed
                return { MainActor.assumeIsolated { self.watchers[id] = nil } }
            }
        )
    }
}

/// A screen that holds whatever requests a test puts on it. Pressing removes
/// the request, as the real card goes once it is answered.
final class FakeScreen: PromptScreen, @unchecked Sendable {
    private let lock = NSLock()
    private var trusted: Bool
    /// A button that takes the press and does nothing.
    private var jammed = false
    private var waiting: [PermissionPrompt] = []
    private var pressedList: [PermissionPrompt] = []
    private var askedCount = 0
    private var lookCount = 0
    private var busy = false
    /// The session in the window, and the ones behind it with what waits
    /// in each.
    private var shown: String?
    private var behind: [String: [PermissionPrompt]] = [:]
    private var stuck: Set<String> = []
    private var openedList: [String] = []

    init(trusted: Bool = true) {
        self.trusted = trusted
    }

    var isTrusted: Bool { lock.withLock { trusted } }
    var isInUse: Bool { lock.withLock { busy } }
    var opened: [String] { lock.withLock { openedList } }
    var showing: String? { lock.withLock { shown } }

    func use(_ busy: Bool) { lock.withLock { self.busy = busy } }
    func showSession(_ title: String) { lock.withLock { shown = title } }
    /// A session behind the window that waits, with these requests in it.
    func park(_ prompts: [PermissionPrompt], in title: String) {
        lock.withLock { behind[title] = prompts }
    }
    /// A row that takes the press and shows nothing.
    func jamRow(_ title: String) { lock.withLock { _ = stuck.insert(title) } }

    func sessions() -> SessionList {
        lock.withLock {
            var rows = behind.keys.sorted().map { title in
                ListedSession(title: title, state: behind[title]?.isEmpty == false ? .awaiting : .idle)
            }
            if let shown { rows.insert(ListedSession(title: shown, state: .running), at: 0) }
            return SessionList(shown: shown, rows: rows) { [weak self] title in
                self?.open(title) ?? false
            }
        }
    }

    private func open(_ title: String) -> Bool {
        lock.withLock {
            openedList.append(title)
            guard !stuck.contains(title) else { return false }
            if title == shown { return true }
            guard let prompts = behind.removeValue(forKey: title) else { return false }
            if let shown { behind[shown] = waiting }
            shown = title
            waiting = prompts
            return true
        }
    }
    var pressed: [PermissionPrompt] { lock.withLock { pressedList } }
    var left: [PermissionPrompt] { lock.withLock { waiting } }
    var asked: Int { lock.withLock { askedCount } }
    var looks: Int { lock.withLock { lookCount } }

    func trust(_ trusted: Bool) { lock.withLock { self.trusted = trusted } }
    func jam(_ jammed: Bool) { lock.withLock { self.jammed = jammed } }
    func show(_ prompt: PermissionPrompt) { lock.withLock { waiting.append(prompt) } }
    func askForTrust() { lock.withLock { askedCount += 1 } }

    func pending() -> [PendingPrompt] {
        let waiting = lock.withLock {
            lookCount += 1
            return self.waiting
        }
        return waiting.map { prompt in
            PendingPrompt(prompt: prompt) { [weak self] in
                guard let self else { return .gone }
                return self.lock.withLock {
                    guard let index = self.waiting.firstIndex(of: prompt) else { return .gone }
                    guard !self.jammed else { return .unanswered(presses: 10, refused: 0) }
                    self.waiting.remove(at: index)
                    self.pressedList.append(prompt)
                    return .answered(presses: 1, seconds: 0.1)
                }
            }
        }
    }

    /// The card as Claude shows it for access to a site.
    static func access(to host: String) -> PermissionPrompt {
        PermissionPrompt(texts: [
            "Allow Claude to ", "access", " ", host, "?",
            "{\n  \"origin\": \"https://\(host)\"\n}"
        ])
    }

    /// A click: the element beside the origin.
    static func click(on host: String) -> PermissionPrompt {
        PermissionPrompt(texts: [
            "Allow Claude to ", "click", " on ", host, "?",
            "{\n  \"ref\": \"ref_600\",\n  \"origin\": \"https://\(host)\"\n}"
        ])
    }

    static func command(_ line: String) -> PermissionPrompt {
        PermissionPrompt(texts: ["Allow Claude to ", "run", "?", "{\"command\": \"\(line)\"}"])
    }
}

/// A clock a test can move.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var moment = Date(timeIntervalSince1970: 1_790_000_000)

    var now: Date { lock.withLock { moment } }

    func advance(by seconds: TimeInterval) { lock.withLock { moment += seconds } }
}
