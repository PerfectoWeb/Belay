import BelayCore
import BelayModules
import Foundation
import Observation

/// The nudge, running: says out loud, and again, when an agent finishes or
/// waits for the person.
///
/// It is told about every snapshot by the controller and has a clock of its
/// own for the reminders, which fall due while nothing else is happening.
@MainActor
@Observable
final class Nudger {
    static let tick: TimeInterval = 15
    /// How many ticks between two looks at what the notification centre says.
    private static let refusalEvery = 4

    var rules: NudgeRules {
        didSet {
            guard rules != oldValue else { return }
            rules.save(to: defaults)
            if isEnabled { Diagnostics.note("nudge rules \(summary)") }
        }
    }
    /// How many sessions wait for the person right now.
    private(set) var waiting = 0
    /// The person said no to notifications in System Settings.
    private(set) var notificationsRefused = false

    /// Handed over by the controller, which owns the notifier.
    @ObservationIgnored var notices: NudgeNotices

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let sounds: NudgeSounds
    @ObservationIgnored private let finder: AgentAppFinding
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var watch = NudgeWatch()
    @ObservationIgnored private var isEnabled = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var ticks = 0
    @ObservationIgnored private var sessions: [NudgeSession] = []
    @ObservationIgnored private var known: [String: SessionState] = [:]
    /// What each session was doing at the last look, for the log.
    @ObservationIgnored private var seen: [String: NudgeSession.Activity] = [:]

    init(
        defaults: UserDefaults = .standard,
        sounds: NudgeSounds = FeedbackSounds(),
        notices: NudgeNotices = NoNotices(),
        finder: AgentAppFinding = AgentAppFinder(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.sounds = sounds
        self.notices = notices
        self.finder = finder
        self.now = now
        rules = NudgeRules.load(from: defaults)
    }

    /// Switched on by the user: the one moment macOS may be asked for
    /// notifications, because the question then follows from what they did.
    func activate() {
        start()
        Task {
            _ = await notices.authorize()
            await refreshRefusal()
        }
    }

    func start() {
        guard !isEnabled else { return }
        isEnabled = true
        let timer = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Diagnostics.note("nudge start \(summary)")
        Task { await refreshRefusal() }
    }

    func stop() {
        isEnabled = false
        timer?.invalidate()
        timer = nil
        watch = NudgeWatch()
        sessions = []
        known = [:]
        seen = [:]
        waiting = 0
        ticks = 0
    }

    /// A new look at the sessions, from the controller.
    func observe(_ snapshot: CoordinatorSnapshot) {
        guard isEnabled else { return }
        known = Dictionary(snapshot.sessions.map { ($0.id.rawValue, $0) }) { first, _ in first }
        sessions = snapshot.sessions.map { session in
            NudgeSession(
                id: session.id.rawValue,
                activity: Self.activity(snapshot.activities[session.id]),
                parent: session.parent?.rawValue)
        }
        noteChanges()
        advance()
    }

    /// One line per change of what a session is doing, as the nudge sees it:
    /// the fused activity, which can lag the transcript by the hook freshness
    /// window. Without it a missing nudge cannot be told from a run the rules
    /// left alone.
    private func noteChanges() {
        var current: [String: NudgeSession.Activity] = [:]
        for session in sessions {
            current[session.id] = session.activity
            if seen[session.id] != session.activity {
                let short = session.id.prefix(8)
                let top = session.parent == nil ? 1 : 0
                let was = seen[session.id].map { "\($0)" } ?? "new"
                Diagnostics.note("nudge sees session(\(short)) \(was)->\(session.activity) top=\(top)")
            }
        }
        seen = current
    }

    /// The clock alone: nothing changed, but a reminder may have fallen due.
    func tick() {
        guard isEnabled else { return }
        advance()
        ticks += 1
        if ticks.isMultiple(of: Self.refusalEvery) { Task { await refreshRefusal() } }
    }

    /// Removing the module: the rules go, the permission stays with macOS.
    func forgetEverything() {
        stop()
        rules = NudgeRules()
        defaults.removeObject(forKey: NudgeRules.defaultsKey)
    }

    private static func activity(_ activity: SessionActivity?) -> NudgeSession.Activity {
        switch activity {
        case .working: .working
        case .awaitingUser: .waiting
        default: .other
        }
    }

    private var summary: String {
        """
        finish=\(rules.finishedSound ? 1 : 0) wait=\(rules.waitingSound ? 1 : 0) \
        quiet=\(rules.quietSound ? 1 : 0) names=\(rules.namesFinished ? 1 : 0) \
        repeatMinutes=\(rules.repeatAfterMinutes) repeatMax=\(rules.repeatAtMost) \
        minimumRun=\(rules.minimumRunSeconds)
        """
    }

    private func advance() {
        let events = watch.advance(sessions, now: now(), rules: rules)
        waiting = watch.waitingCount
        say(events)
    }

    /// One note per kind however many sessions happened at once, and only
    /// the kinds the person left on.
    private func say(_ events: [NudgeEvent]) {
        var notes: Set<Feedback.Sound> = []
        for event in events {
            switch event {
            case .finished(let session, let ran): finished(session, ran: ran, notes: &notes)
            case .waiting: note(.nudgeWaiting, if: rules.waitingSound, kind: "waiting", in: &notes)
            case .quiet: note(.nudgeQuiet, if: rules.quietSound, kind: "quiet", in: &notes)
            case .reminder(let session, let waited, _):
                announce(reminder: session, waited: waited)
                Diagnostics.note("nudge said kind=reminder")
            case .resumed: break
            }
        }
        let order: [Feedback.Sound] = [.nudgeWaiting, .nudgeFinished, .nudgeQuiet]
        for sound in order where notes.contains(sound) { sounds.play(sound) }
    }

    private func note(
        _ sound: Feedback.Sound, if isOn: Bool, kind: String, in notes: inout Set<Feedback.Sound>
    ) {
        guard isOn else { return }
        notes.insert(sound)
        Diagnostics.note("nudge said kind=\(kind)")
    }

    private func finished(_ session: String, ran: TimeInterval, notes: inout Set<Feedback.Sound>) {
        guard rules.finishedSound || rules.namesFinished else { return }
        if rules.finishedSound { notes.insert(.nudgeFinished) }
        if rules.namesFinished { announce(finished: session, ran: ran) }
        Diagnostics.note("nudge said kind=finished")
    }

    private func announce(finished session: String, ran: TimeInterval) {
        let took = ElapsedTime.spoken(ran)
        let body =
            known[session]?.workspace.map {
                String(localized: "The agent in \($0) finished a run of \(took).")
            } ?? String(localized: "An agent finished a run of \(took).")
        notices.post(
            title: String(localized: "An agent finished"), body: body, raising: app(of: session))
    }

    private func announce(reminder session: String, waited: TimeInterval) {
        let spoken = ElapsedTime.spoken(waited)
        let body =
            known[session]?.workspace.map {
                String(localized: "The agent in \($0) has been waiting for \(spoken).")
            } ?? String(localized: "An agent has been waiting for \(spoken).")
        notices.post(
            title: String(localized: "Still waiting for you"), body: body, raising: app(of: session))
    }

    private func app(of session: String) -> String? {
        guard let state = known[session] else { return nil }
        return finder.bundleID(provider: state.provider, session: state.id)
    }

    private func refreshRefusal() async {
        let refused = await notices.isRefused()
        if isEnabled { notificationsRefused = refused }
    }
}
