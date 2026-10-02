import Foundation

/// One session as the nudge sees it: what it is doing, and whose subagent it
/// is. Plain strings, so the package needs nothing of the app's own types.
public struct NudgeSession: Equatable, Sendable {
    public enum Activity: Equatable, Sendable {
        case working
        /// Blocked on the person.
        case waiting
        /// Idle, ended, or not known.
        case other
    }

    public var id: String
    public var activity: Activity
    public var parent: String?
    /// Something beside a hook has seen the session: a transcript, a
    /// process. A session known from one prompt hook alone can vanish for
    /// reasons that are not news, such as Codex resuming an old thread under
    /// a new id, and is never reported as gone quiet.
    public var isEvidenced: Bool

    public init(id: String, activity: Activity, parent: String? = nil, isEvidenced: Bool = true) {
        self.id = id
        self.activity = activity
        self.parent = parent
        self.isEvidenced = isEvidenced
    }
}

/// What is worth saying, decided by comparing one look at the sessions with
/// the one before.
public enum NudgeEvent: Equatable, Sendable {
    /// A run ended, and lasted `ran` of actual work.
    case finished(session: String, ran: TimeInterval)
    case waiting(session: String)
    /// Still waiting: the `count`th reminder, `waited` after the first wait.
    case reminder(session: String, waited: TimeInterval, count: Int)
    /// A working session vanished without finishing.
    case quiet(session: String)
    /// A session stopped waiting.
    case resumed(session: String)
}

/// The nudge's memory. Pure: the clock and the rules are handed in, and
/// nothing here touches the system.
public struct NudgeWatch: Sendable {
    private struct Track {
        var activity: NudgeSession.Activity
        var isTopLevel: Bool
        /// Sticky: once anything but a hook has seen the session, it stays seen.
        var isEvidenced = false
        /// Work done in earlier stretches of the run, before it paused to wait.
        var worked: TimeInterval = 0
        var workingSince: Date?
        var waitingSince: Date?
        var lastReminder: Date?
        var reminders = 0
    }

    private var tracks: [String: Track] = [:]

    public init() {}

    /// How many sessions wait for the person right now.
    public var waitingCount: Int {
        tracks.values.filter { $0.activity == .waiting }.count
    }

    /// Finishes and going quiet concern the session the person started: a
    /// workflow of fifty subagents would otherwise ring fifty times. Waiting
    /// concerns every session, because a subagent that asks for permission
    /// stops the whole run.
    public mutating func advance(
        _ sessions: [NudgeSession], now: Date, rules: NudgeRules
    ) -> [NudgeEvent] {
        var events: [NudgeEvent] = []
        for session in sessions {
            var track = tracks[session.id]
            events += step(&track, to: session, now: now, rules: rules)
            tracks[session.id] = track
        }
        events += vanished(from: sessions, now: now, rules: rules)
        return events
    }

    private func step(
        _ track: inout Track?, to session: NudgeSession, now: Date, rules: NudgeRules
    ) -> [NudgeEvent] {
        let before = track?.activity
        var current = track ?? Track(activity: session.activity, isTopLevel: session.parent == nil)
        current.isTopLevel = session.parent == nil
        current.isEvidenced = current.isEvidenced || session.isEvidenced
        defer { track = current }

        let events: [NudgeEvent]
        switch session.activity {
        case .working: events = works(&current, after: before, session.id, now)
        case .waiting: events = waits(&current, after: before, session.id, now, rules)
        case .other: events = rests(&current, after: before, session.id, now, rules)
        }
        current.activity = session.activity
        return events
    }

    private func works(
        _ track: inout Track, after before: NudgeSession.Activity?, _ id: String, _ now: Date
    ) -> [NudgeEvent] {
        if before == nil || before == .other { track.worked = 0 }
        if before != .working { track.workingSince = now }
        track.waitingSince = nil
        return before == .waiting ? [.resumed(session: id)] : []
    }

    private func waits(
        _ track: inout Track,
        after before: NudgeSession.Activity?,
        _ id: String,
        _ now: Date,
        _ rules: NudgeRules
    ) -> [NudgeEvent] {
        if before == .working, let since = track.workingSince {
            track.worked += now.timeIntervalSince(since)
        }
        track.workingSince = nil
        if before != .waiting {
            track.waitingSince = now
            track.lastReminder = nil
            track.reminders = 0
            return [.waiting(session: id)]
        }
        guard let due = reminder(for: track, id: id, now: now, rules: rules) else { return [] }
        track.lastReminder = now
        track.reminders += 1
        return [due]
    }

    private func rests(
        _ track: inout Track,
        after before: NudgeSession.Activity?,
        _ id: String,
        _ now: Date,
        _ rules: NudgeRules
    ) -> [NudgeEvent] {
        var events: [NudgeEvent] = []
        if before == .working, track.isTopLevel, let since = track.workingSince {
            let ran = track.worked + now.timeIntervalSince(since)
            if ran >= TimeInterval(rules.minimumRunSeconds) {
                events.append(.finished(session: id, ran: ran))
            }
        }
        if before == .waiting { events.append(.resumed(session: id)) }
        track.worked = 0
        track.workingSince = nil
        track.waitingSince = nil
        return events
    }

    /// Due once `repeatAfterMinutes` have passed since the last word on this
    /// wait, and never more than `repeatAtMost` times.
    private func reminder(
        for track: Track, id: String, now: Date, rules: NudgeRules
    ) -> NudgeEvent? {
        guard rules.repeatAfterMinutes > 0, track.reminders < rules.repeatAtMost,
            let since = track.waitingSince
        else { return nil }
        let gap = TimeInterval(rules.repeatAfterMinutes) * 60
        guard now >= (track.lastReminder ?? since).addingTimeInterval(gap) else { return nil }
        return .reminder(
            session: id, waited: now.timeIntervalSince(since), count: track.reminders + 1)
    }

    /// A working session that is gone, with nothing left that descends from
    /// it, went quiet. A session that finished said so first and left
    /// `working` before it went. The minimum run applies here as to a
    /// finish: a session closed seconds after it was opened is not news, and
    /// neither is one nothing but a hook ever saw.
    private mutating func vanished(
        from sessions: [NudgeSession], now: Date, rules: NudgeRules
    ) -> [NudgeEvent] {
        let live = Set(sessions.map(\.id))
        var events: [NudgeEvent] = []
        for id in tracks.keys.sorted() where !live.contains(id) {
            guard let track = tracks.removeValue(forKey: id) else { continue }
            guard track.activity == .working, track.isTopLevel, track.isEvidenced,
                !sessions.contains(where: { $0.parent == id })
            else { continue }
            let ran = track.worked + (track.workingSince.map { now.timeIntervalSince($0) } ?? 0)
            guard ran >= TimeInterval(rules.minimumRunSeconds) else { continue }
            events.append(.quiet(session: id))
        }
        return events
    }
}
