import BelayCore
import Foundation

/// Decides what is worth telling the user, by diffing successive snapshots.
///
/// Pure and separate from `Notifier` so the "when" is testable without a
/// notification centre, and so the controller stays about wiring.
struct AnnouncementTrigger {
    enum Announcement: Equatable {
        case needsInput(session: SessionID, workspace: String?)
        case finished(duration: TimeInterval, workspace: String?)
        case releasedForSafety(SuspensionReason)
        /// A session stopped waiting, so it may be announced again later.
        case resumed(SessionID)
        /// A working session vanished without ever saying it had finished.
        case wentQuiet(session: SessionID, workspace: String?)
    }

    private var waiting: Set<SessionID> = []
    /// Sessions last seen working, and the workspace to name if one goes quiet.
    /// A session that says `Stop` leaves this set before it is evicted, so an
    /// ordinary finish never reaches `wentQuiet`.
    private var working: [SessionID: String?] = [:]
    private var holdStarted: Date?
    private var lastWorkspace: String?
    private var lastState: BelayState = .armed

    mutating func diff(_ snapshot: CoordinatorSnapshot, now: Date = Date()) -> [Announcement] {
        var announcements: [Announcement] = []

        let nowWaiting = Set(
            snapshot.sessions.filter { snapshot.activities[$0.id] == .awaitingUser }.map(\.id)
        )
        for session in nowWaiting.subtracting(waiting) {
            let workspace = snapshot.sessions.first { $0.id == session }?.workspace
            announcements.append(.needsInput(session: session, workspace: workspace))
        }
        for session in waiting.subtracting(nowWaiting) {
            announcements.append(.resumed(session))
        }
        waiting = nowWaiting

        announcements += quiet(snapshot)

        // Remember a workspace while we have one: by the time the hold ends the
        // session is usually already gone from the snapshot.
        if let workspace = snapshot.sessions.first?.workspace { lastWorkspace = workspace }

        switch (holdStarted, snapshot.holdingSince) {
        case (nil, let started?):
            holdStarted = started
        case (let previous?, nil):
            let duration = now.timeIntervalSince(previous)
            announcements.append(.finished(duration: duration, workspace: lastWorkspace))
            holdStarted = nil
        default:
            break
        }

        // Compared on the case, not the payload: `batteryLow` carries the charge,
        // so at 1% granularity every few minutes of discharge produced a fresh
        // state and another "Belay stopped holding" banner.
        let isSuspended = {
            guard case .suspended = snapshot.state else { return false }
            return true
        }()
        let wasSuspended = {
            guard case .suspended = lastState else { return false }
            return true
        }()
        if case .suspended(let reason) = snapshot.state, isSuspended, !wasSuspended {
            announcements.append(.releasedForSafety(reason))
        }
        lastState = snapshot.state

        return Self.resolvingContradiction(in: announcements)
    }

    /// A session that vanished mid-work also ends the hold, so both rules fire
    /// on the same tick. Only one of them is true: "your task finished, it took
    /// ten minutes" is exactly the wrong thing to say about a run that died.
    /// The honest one wins and the other is dropped.
    private static func resolvingContradiction(in announcements: [Announcement]) -> [Announcement] {
        let quiet = announcements.contains { if case .wentQuiet = $0 { true } else { false } }
        guard quiet else { return announcements }
        return announcements.filter { if case .finished = $0 { false } else { true } }
    }

    /// A session counts as quiet only when its whole family has gone.
    ///
    /// The parent waiting while a subagent works is not silence, and neither is
    /// a parent that has been evicted while its children are still running: the
    /// work is going on, whatever the tree looks like. So a vanished session is
    /// announced only when nothing left in the snapshot descends from it.
    ///
    /// The signal is the disappearance itself. A session that stops emitting —
    /// a CLI that lost its authorisation, a killed process, a closed terminal —
    /// stays `.working` until its TTL evicts it, while one that finishes says so
    /// first and leaves `working` before it goes.
    private mutating func quiet(_ snapshot: CoordinatorSnapshot) -> [Announcement] {
        var announcements: [Announcement] = []
        let live = Set(snapshot.sessions.map(\.id))

        for session in snapshot.sessions {
            switch snapshot.activities[session.id] {
            case .working:
                // `updateValue`, not the subscript: assigning nil through the
                // subscript of a dictionary of optionals removes the key, and a
                // working session in a workspace we cannot name would then never
                // be tracked at all.
                working.updateValue(session.workspace, forKey: session.id)
            case .none:
                break
            default:
                working.removeValue(forKey: session.id)
            }
        }

        for (id, workspace) in working where !live.contains(id) {
            working.removeValue(forKey: id)
            guard !snapshot.sessions.contains(where: { $0.parent == id }) else { continue }
            announcements.append(.wentQuiet(session: id, workspace: workspace))
        }
        return announcements
    }
}
