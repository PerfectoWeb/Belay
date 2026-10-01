import BelayCore
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

/// The nudge's sound: a list of what was asked for.
@MainActor
final class FakeSounds: NudgeSounds {
    private(set) var played: [Feedback.Sound] = []

    func play(_ sound: Feedback.Sound) { played.append(sound) }
    func clear() { played.removeAll() }
}

/// The nudge's banners: what was posted, and what macOS would answer.
@MainActor
final class FakeNotices: NudgeNotices {
    struct Banner: Equatable {
        let title: String
        let body: String
        let bundleID: String?
    }

    private(set) var posted: [Banner] = []
    private(set) var asked = 0
    var refused = false

    func post(title: String, body: String, raising bundleID: String?) {
        posted.append(Banner(title: title, body: body, bundleID: bundleID))
    }

    func authorize() async -> Bool {
        asked += 1
        return !refused
    }

    func isRefused() async -> Bool { refused }
}

/// Which app each session lives in, as a test wants it.
@MainActor
final class FakeAgentApps: AgentAppFinding {
    private var apps: [SessionID: String] = [:]

    func seat(_ session: String, in bundleID: String) {
        apps[SessionID(session)] = bundleID
    }

    func bundleID(provider: ProviderID, session: SessionID) -> String? {
        apps[session]
    }
}

/// A process table that is a dictionary.
struct FakeAncestry: ProcessAncestry {
    var apps: [pid_t: String] = [:]
    var parents: [pid_t: pid_t] = [:]

    func owningApp(ofPid pid: pid_t) -> String? {
        ProcessWalk.owner(of: pid, parent: { parents[$0] }, app: { apps[$0] })
    }
}

/// A process table a test writes by hand. Ending a process removes its row,
/// unless the test made it stubborn.
final class FakeProcesses: ProcessSource, @unchecked Sendable {
    static let epoch = Date(timeIntervalSince1970: 1_790_000_000)

    private let lock = NSLock()
    private var rows: [ProcessSnapshot] = []
    private var registry: [pid_t: Date] = [:]
    private var readable = true
    private var stubborn: Set<pid_t> = []
    private var readCount = 0
    private var termed: [pid_t] = []

    /// How often the table was read.
    var reads: Int { lock.withLock { readCount } }
    /// Who was sent SIGTERM, in order.
    var signalled: [pid_t] { lock.withLock { termed } }

    func put(
        _ pid: pid_t, _ name: String, parent: pid_t = 1, started: TimeInterval = 0,
        cpu: Double? = nil
    ) {
        let row = ProcessSnapshot(
            pid: pid, parent: parent, name: name,
            startedAt: Self.epoch.addingTimeInterval(started), cpuSeconds: cpu)
        lock.withLock {
            rows.removeAll { $0.pid == pid }
            rows.append(row)
        }
    }

    func drop(_ pid: pid_t) { lock.withLock { rows.removeAll { $0.pid == pid } } }

    func register(_ pid: pid_t, writtenAt seconds: TimeInterval) {
        lock.withLock { registry[pid] = Self.epoch.addingTimeInterval(seconds) }
    }

    func makeReadable(_ readable: Bool) { lock.withLock { self.readable = readable } }
    func ignoreSignals(from pid: pid_t) { lock.withLock { _ = stubborn.insert(pid) } }

    func table() -> [ProcessSnapshot]? {
        lock.withLock {
            readCount += 1
            return readable ? rows : nil
        }
    }

    func cpuSeconds(of pids: [pid_t]) -> [pid_t: Double] { [:] }
    func sessionRegistry() -> [pid_t: Date] { lock.withLock { registry } }

    func terminate(_ pid: pid_t) -> Bool {
        lock.withLock {
            termed.append(pid)
            if !stubborn.contains(pid) { rows.removeAll { $0.pid == pid } }
            return true
        }
    }
}
