import BelayModules
import Foundation
import Observation

/// The automatic approval, running: looks at the chosen apps every couple of
/// seconds and presses Allow once on the requests the rules cover.
@MainActor
@Observable
final class AutoAllower {
    /// A request answered two seconds late is answered at once as far as an
    /// agent is concerned, and the look costs a tenth of a second of reading.
    static let interval: TimeInterval = 2
    /// Requests come in runs: an agent clicking through a page asks every few
    /// seconds. For a while after one was seen the looks come closer together,
    /// so that the person watching is not the faster of the two.
    static let quickInterval: TimeInterval = 0.5
    static let quickSpell: TimeInterval = 60
    static let untilKey = "BelayAutoAllowUntil"

    enum Standing: Equatable {
        case off
        /// Every app's agent is switched off in Agents, and a module does
        /// nothing for an agent Belay was told to leave alone.
        case agentOff
        case needsAccess
        case watching
    }

    var rules: AutoAllowRules {
        didSet {
            guard rules != oldValue else { return }
            rules.save(to: defaults)
            if rules.duration != oldValue.duration, isRunning { stampDeadline() }
            if isRunning { Diagnostics.note("autoallow rules \(settings)") }
        }
    }
    private(set) var log: AutoAllowLog
    private(set) var standing: Standing = .off {
        didSet {
            guard standing != oldValue else { return }
            Diagnostics.note("autoallow standing=\(standing)")
        }
    }
    /// When it switches itself off, if it does.
    private(set) var deadline: Date?

    /// The time ran out: the owner switches the module off.
    @ObservationIgnored var onExpired: () -> Void = {}
    /// Whether the agent behind an app is switched on in Agents.
    @ObservationIgnored var agentIsOn: (AutoAllowRules.App) -> Bool = { _ in true }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let screens: [AutoAllowRules.App: PromptScreen]
    @ObservationIgnored private let now: @Sendable () -> Date
    /// How long a request may take to be drawn once its session is in the
    /// window.
    @ObservationIgnored private let patience: TimeInterval
    @ObservationIgnored private var visits: [AutoAllowRules.App: SessionVisits] = [:]
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var isLooking = false
    @ObservationIgnored private var lastSeen: Date?
    @ObservationIgnored private var lastLook: Date?
    /// Who asked for a look while one was under way.
    @ObservationIgnored private var waiting: [@MainActor () -> Void]?
    private var isRunning: Bool { timer != nil }

    init(
        defaults: UserDefaults = .standard,
        screens: [AutoAllowRules.App: PromptScreen] = PromptScreens.forThisChannel,
        patience: TimeInterval = 2,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.screens = screens
        self.patience = patience
        self.now = now
        rules = AutoAllowRules.load(from: defaults)
        log = AutoAllowLog.load(from: defaults)
    }

    /// Switched on by the user: the clock starts here, and macOS is asked for
    /// Accessibility if Belay does not have it.
    func activate() {
        stampDeadline()
        start()
        desks.first { !$0.screen.isTrusted }?.screen.askForTrust()
    }

    func start() {
        guard timer == nil else { return }
        let stamp = defaults.double(forKey: Self.untilKey)
        deadline = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
        let timer = Timer(timeInterval: Self.quickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.beat() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        let left = deadline.map { "\(max(0, Int($0.timeIntervalSince(now()) / 60)))" } ?? "never"
        Diagnostics.note("autoallow start \(settings) minutesLeft=\(left)")
        standing = current
        tick()
    }

    private var settings: String {
        "scope=\(rules.scope.rawValue) behind=\(rules.reachesBehind ? 1 : 0) duration=\(Int(rules.duration))"
    }

    /// Every app this build can read, in one order.
    private var desks: [AutoAllowDesk] {
        AutoAllowRules.App.allCases.compactMap { app in
            guard let screen = screens[app] else { return nil }
            return AutoAllowDesk(app: app, screen: screen, visits: visits[app] ?? SessionVisits())
        }
    }

    /// The apps whose agent is switched off in Agents, and so left alone.
    var appsLeftAlone: [AutoAllowRules.App] {
        desks.map(\.app).filter { !agentIsOn($0) }
    }

    private var current: Standing {
        let desks = desks.filter { agentIsOn($0.app) }
        guard !desks.isEmpty else { return .agentOff }
        return desks.allSatisfy(\.screen.isTrusted) ? .watching : .needsAccess
    }

    /// Belay is quitting. The deadline stays on record, so a restart cannot
    /// buy the switch more time than it was given.
    func stop() {
        timer?.invalidate()
        timer = nil
        standing = .off
    }

    /// Switched off, by the user or by the clock.
    func deactivate() {
        stop()
        deadline = nil
        defaults.removeObject(forKey: Self.untilKey)
    }

    private func stampDeadline() {
        deadline = rules.deadline(from: now())
        if let deadline {
            defaults.set(deadline.timeIntervalSince1970, forKey: Self.untilKey)
        } else {
            defaults.removeObject(forKey: Self.untilKey)
        }
    }

    /// The timer's beat: a look when one is due, which is every beat during
    /// a run of requests and every fourth otherwise.
    private func beat() {
        let moment = now()
        let isQuick = lastSeen.map { moment.timeIntervalSince($0) < Self.quickSpell } ?? false
        let due = isQuick ? Self.quickInterval : Self.interval
        if let lastLook, moment.timeIntervalSince(lastLook) < due - 0.05 { return }
        tick()
    }

    func tick(then finished: @escaping @MainActor () -> Void = {}) {
        guard isRunning else { return finished() }
        if let deadline, now() >= deadline {
            Diagnostics.note("autoallow expired")
            onExpired()
            return finished()
        }
        standing = current
        guard standing == .watching else { return finished() }
        guard !isLooking else {
            // Never dropped: what came up during this look is seen by the
            // next, straight after.
            waiting = (waiting ?? []) + [finished]
            return
        }
        isLooking = true
        lastLook = now()
        let desks = desks.filter { agentIsOn($0.app) }
        let rules = rules
        let patience = patience
        // Asked here and not in the look: whether the person is at work is
        // a question about this moment.
        let mayReachBehind = rules.reachesBehind && !desks.contains { $0.screen.isInUse }
        Task { [weak self] in
            let looks = await Task.detached(priority: .utility) {
                desks.map { desk in
                    let look = AutoAllowLook.take(
                        at: desk, rules: rules, mayReachBehind: mayReachBehind, patience: patience)
                    return (desk.app, look)
                }
            }.value
            self?.isLooking = false
            for (app, look) in looks { self?.record(look, in: app) }
            self?.lookAgain()
            finished()
        }
    }

    private func record(_ look: AutoAllowLook, in app: AutoAllowRules.App) {
        visits[app] = look.visits
        if let reach = look.reach {
            // The session's name stays out of the log, as the sites do.
            Diagnostics.note("autoallow behind=\(reach.rawValue) app=\(app.rawValue)")
        }
        guard !look.isEmpty else { return }
        // Counts and the scope. The site is in the list the user can see,
        // not in a log file they may be asked to send. A request that waits
        // repeats this line, and the log folds repeats into one.
        Diagnostics.note(
            """
            autoallow approved=\(look.approved.count) held=\(look.held) \
            failed=\(look.failed) beaten=\(look.beaten) presses=\(look.presses) \
            took=\(String(format: "%.1f", look.seconds)) scope=\(rules.scope.rawValue) \
            app=\(app.rawValue)\(look.refused == 0 ? "" : " refused=\(look.refused)")
            """)
        lastSeen = now()
        // Switched off while the look was under way: what it pressed still
        // happened, and still belongs in the list.
        guard !look.approved.isEmpty else { return }
        for subject in look.approved { log.record(subject, at: now()) }
        log.save(to: defaults)
    }

    private func lookAgain() {
        guard let waiting else { return }
        self.waiting = nil
        tick { waiting.forEach { $0() } }
    }

    /// Removing the module: the rules and the list go, the Accessibility
    /// grant stays with macOS.
    func forgetEverything() {
        deactivate()
        rules = AutoAllowRules()
        log = AutoAllowLog()
        defaults.removeObject(forKey: AutoAllowRules.defaultsKey)
        defaults.removeObject(forKey: AutoAllowLog.defaultsKey)
    }
}
