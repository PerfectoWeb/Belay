import Foundation
import VigilCore

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
    }

    private var waiting: Set<SessionID> = []
    private var holdStarted: Date?
    private var lastWorkspace: String?
    private var lastState: VigilState = .armed

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
        // state and another "Vigil stopped holding" banner.
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

        return announcements
    }
}
