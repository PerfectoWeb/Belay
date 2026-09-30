import BelayModules
import BelaySupport
import Foundation
import Observation

/// The screenshot cleaner, running: a slow timer, a pass over the folders, and
/// the numbers the Settings card shows.
///
/// Five minutes between passes. A screenshot that is due at four hours and
/// leaves at four hours and three minutes is on time by any measure a person
/// would use, and a folder listing twelve times an hour costs nothing.
@MainActor
@Observable
final class ScreenshotCleaner {
    static let interval: TimeInterval = 300
    static let tallyKey = "BelayScreenshotCleanerTrashed"
    static let sinceKey = "BelayScreenshotCleanerSince"

    var rules: ScreenshotRules {
        didSet {
            guard rules != oldValue else { return }
            rules.save(to: defaults)
            if isRunning { Diagnostics.note("screenshots rules \(settings)") }
        }
    }
    /// Everything this module ever moved to the Trash on this Mac.
    private(set) var trashedTotal: Int
    /// Folders the last pass could not list, as paths.
    private(set) var unreadable: [String] = []
    private(set) var isRunning = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let sweeper: ScreenshotSweeper
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var isSweeping = false
    /// What the last pass that was written down had left alone.
    @ObservationIgnored private var lastLeft: [Int]?
    /// A pass asked for while one was running, and who is waiting on it.
    @ObservationIgnored private var queued: (pass: Pass, waiting: [@MainActor () -> Void])?

    init(
        defaults: UserDefaults = .standard,
        sweeper: ScreenshotSweeper = ScreenshotCleaner.sweeper(
            through: ScreenshotFolderAccess.provider),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.sweeper = sweeper
        self.now = now
        rules = ScreenshotRules.load(from: defaults)
        trashedTotal = defaults.integer(forKey: Self.tallyKey)
    }

    /// When the cleaner was last switched on. Automatic passes count no
    /// screenshot's age from before this moment.
    var activeSince: Date? {
        let stamp = defaults.double(forKey: Self.sinceKey)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    /// Switched on by the user, as opposed to started at launch: this is the
    /// moment the grace is counted from.
    func activate() {
        defaults.set(now().timeIntervalSince1970, forKey: Self.sinceKey)
        start()
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sweep(.automatic) }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        isRunning = true
        Diagnostics.note("screenshots start \(settings) grace=\(activeSince == nil ? 0 : 1)")
        sweep(.automatic)
    }

    /// The rules as the log states them. How many folders, never which.
    private var settings: String {
        """
        age=\(Int(rules.age)) folders=\(rules.folders.count) \
        keepsTouched=\(rules.keepsTouched ? 1 : 0) recordings=\(rules.includesRecordings ? 1 : 0)
        """
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        let waiting = queued?.waiting ?? []
        queued = nil
        waiting.forEach { $0() }
    }

    enum Pass {
        /// The timer's. Honours the grace.
        case automatic
        /// "Clean Up Now". Everything past its age goes, grace or not.
        case requested
    }

    /// One pass, off the main thread: a folder on a sleeping disk or a network
    /// share can take seconds to answer, and the panel must not wait for it.
    func sweep(_ pass: Pass, then finished: @escaping @MainActor () -> Void = {}) {
        guard !rules.folders.isEmpty else {
            finished()
            return
        }
        guard !isSweeping else {
            // Never dropped: "Clean Up Now" pressed during the timer's pass
            // still has to happen. A requested pass outranks an automatic one.
            let pass: Pass = queued?.pass == .requested ? .requested : pass
            queued = (pass, (queued?.waiting ?? []) + [finished])
            return
        }
        isSweeping = true
        let rules = rules
        let sweeper = sweeper
        let moment = now()
        let floor = pass == .automatic ? activeSince : nil
        Task.detached(priority: .utility) { [weak self] in
            let report = sweeper.run(rules: rules, now: moment, notBefore: floor)
            await MainActor.run {
                self?.record(report)
                finished()
            }
        }
    }

    nonisolated static func sweeper(through access: FileAccessProvider) -> ScreenshotSweeper {
        ScreenshotSweeper(
            list: { folder in
                try access.withAccess(to: folder) { try ScreenshotFolder.candidates(in: $0) }
            },
            trash: { url in
                try access.withAccess(to: url) { try ScreenshotTrash.move($0) }
            }
        )
    }

    private func record(_ report: SweepReport) {
        isSweeping = false
        defer { runQueued() }
        unreadable = report.unreadable.map(\.path)
        let acted = report.trashed > 0 || report.failed > 0 || !report.unreadable.isEmpty
        // A quiet pass is written down only when what it left alone changed:
        // twelve passes an hour over the same desk are one fact.
        let left = [report.kept, report.waiting]
        guard acted || left != lastLeft else { return }
        lastLeft = left
        if report.trashed > 0 {
            trashedTotal += report.trashed
            defaults.set(trashedTotal, forKey: Self.tallyKey)
        }
        // Counts only. Which files, and where, is nobody's business but the
        // Trash's.
        Diagnostics.note(
            """
            screenshots trashed=\(report.trashed) failed=\(report.failed) \
            unreadable=\(report.unreadable.count) kept=\(report.kept) \
            waiting=\(report.waiting)\(report.firstFailure.map { " why=\($0)" } ?? "")
            """)
    }

    private func runQueued() {
        guard let next = queued else { return }
        queued = nil
        sweep(next.pass) { next.waiting.forEach { $0() } }
    }

    func add(folder: URL) {
        let path = folder.standardizedFileURL.path
        guard !rules.folders.contains(path), ScreenshotFolderAccess.remember(folder) else { return }
        rules.folders.append(path)
        if isRunning { sweep(.automatic) }
    }

    func remove(folder path: String) {
        rules.folders.removeAll { $0 == path }
        unreadable.removeAll { $0 == path }
        ScreenshotFolderAccess.forget(URL(fileURLWithPath: path, isDirectory: true))
    }

    /// Removing the module: the grants, the rules and the tally all go, so
    /// installing it again starts from nothing.
    func forgetEverything() {
        stop()
        for path in rules.folders {
            ScreenshotFolderAccess.forget(URL(fileURLWithPath: path, isDirectory: true))
        }
        rules = ScreenshotRules()
        trashedTotal = 0
        unreadable = []
        defaults.removeObject(forKey: ScreenshotRules.defaultsKey)
        defaults.removeObject(forKey: Self.tallyKey)
        defaults.removeObject(forKey: Self.sinceKey)
    }
}
