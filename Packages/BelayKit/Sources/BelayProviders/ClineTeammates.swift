import BelayCore
import BelaySupport
import Foundation

/// Cline's teammates, the way its team mode writes them: one
/// `<agent>__<suffix>.messages.json` per spawned agent, inside the parent
/// session's directory, with no state file of their own. Growth is their only
/// vocabulary — appear and grow means working, silence means idle, and the
/// parent's ending is theirs. A teammate is a session in its own right, like
/// a Claude Code subagent: tracked separately, *presented* under its parent.
extension ClineProvider {
    @discardableResult
    func ingestTeammate(
        session sessionID: String, stem: String, agent: String, now: Date, atStartup: Bool = false
    ) -> Bool {
        let id = SessionID(stem)
        let parent = SessionID(sessionID)
        let url = configuration.sessionsDirectory
            .appendingPathComponent(sessionID, isDirectory: true)
            .appendingPathComponent("\(stem).messages.json")
        guard let snapshot = FileSnapshot(url: url) else {
            if watched[id] != nil { end(id, at: now, cause: "teammate-gone") }
            return false
        }
        if var watch = watched[id] {
            // Any change in size is a write, not just growth: a shrink means the
            // file was truncated or replaced (context compaction, a checkpoint
            // restore). Resetting the high-water mark on a shrink is essential —
            // growth is a teammate's *only* signal, so without this a working
            // teammate whose file shrank goes dark until it re-exceeds its old
            // maximum, which may be never.
            guard snapshot.size != watch.messagesBytes else { return false }
            watch.messagesBytes = snapshot.size
            watch.lastWriteAt = now
            watched[id] = watch
            return report(.working, for: id, at: now)
        }

        var watch = ClineWatch(
            id: id,
            stateURL: ClineSessions.stateURL(id: sessionID, under: configuration.sessionsDirectory),
            parent: parent,
            kind: agent,
            workspace: watched[parent]?.workspace,
            lastWriteAt: atStartup ? snapshot.modified : now,
            messagesBytes: snapshot.size,
            reported: nil,
            messagesURL: url)

        if atStartup {
            // The launch discipline the roots follow: the stale are not
            // followed, the merely old are followed but silent until they
            // actually move.
            let age = now.timeIntervalSince(snapshot.modified)
            guard age <= configuration.staleAtStartupAfter else { return false }
            watched[id] = watch
            guard age <= configuration.inferredIdleAfter else { return false }
        } else {
            watched[id] = watch
        }
        EventLog.note("cline teammate start \(id) of \(parent) agent=\(agent)")
        return report(.working, for: id, at: now)
    }

    /// Called when a root is first followed, so teammates that already exist
    /// are not invisible until their next write.
    func seedTeammates(of sessionID: String, now: Date, atStartup: Bool) {
        let files = ClineSessions.teammateFiles(
            inSession: sessionID, under: configuration.sessionsDirectory, access: access)
        for file in files {
            ingestTeammate(
                session: sessionID, stem: file.stem, agent: file.agent, now: now,
                atStartup: atStartup)
        }
    }

    /// A teammate does not outlive its parent: the whole directory is one
    /// conversation, and the parent's ending closes it.
    func endTeammates(of parent: SessionID, at now: Date, cause: String) {
        for (id, watch) in watched where watch.parent == parent {
            end(id, at: now, cause: cause)
        }
    }
}
