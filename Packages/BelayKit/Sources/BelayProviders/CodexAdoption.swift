import BelayCore
import BelaySupport
import Foundation

/// How a rollout becomes a watch: found at startup, or appearing while Belay
/// runs. Beside the provider for the file-length rule, mirroring
/// `ClaudeCodeAdoption`.
extension CodexProvider {
    @discardableResult
    func adopt(_ url: URL, id: SessionID, now: Date, atStartup: Bool) -> Bool {
        guard let snapshot = FileSnapshot(url: url) else { return false }
        var watch = CodexWatch(
            id: id,
            url: url,
            lastWriteAt: atStartup ? snapshot.modified : now,
            workspace: CodexRollout.workspace(atHeadOf: url, access: access))

        guard !atStartup else {
            // Same launch discipline as Claude Code: history is not followed,
            // the merely old is followed but silent, and only a rollout fresh
            // enough to be a live turn gets its tail classified.
            let age = now.timeIntervalSince(snapshot.modified)
            guard age <= configuration.staleAtStartupAfter else { return false }
            guard age <= configuration.inferredIdleAfter else {
                watch.cursor.seed(.endOfFile, snapshot: snapshot)
                watched[id] = watch
                return false
            }
            watch.cursor.seed(.tailWindow, snapshot: snapshot)
            watched[id] = watch
            return ingest(url, now: now) || reportUnlessClassified(id, at: now)
        }

        // A rollout that appears while we are running is usually a turn
        // starting. Usually: Codex Desktop's importer writes rollouts for
        // other agents' month-old conversations, complete with a fresh mtime
        // and a `task_started` in the tail. The record clocks cannot be
        // bumped from outside, so an old tail opens nothing and the file is
        // followed silently from its end (same rule as the Claude provider).
        watch.cursor.seed(.tailWindow, snapshot: snapshot)
        let delta = watch.cursor.read(using: access)
        let newest = CodexRollout.newestTimestamp(in: delta.lines)
        if let newest, now.timeIntervalSince(newest) > configuration.staleAtStartupAfter {
            if let current = FileSnapshot(url: url) {
                watch.cursor.seed(.endOfFile, snapshot: current)
            }
            watched[id] = watch
            EventLog.note("codex stale-touch \(id) ws=\(watch.workspace ?? "?")")
            return false
        }
        watched[id] = watch
        EventLog.note("codex session start \(id) ws=\(watch.workspace ?? "?")")
        return absorb(delta, id: id, now: now) || reportUnlessClassified(id, at: now)
    }

    /// The adopt fallback: bytes arrived but the tail carried no marker, so
    /// call it working. A tail that *was* classified — even into a silent
    /// first idle — already had its say, and forcing `.working` over it is
    /// exactly how a housekeeping pass over old rollouts becomes a panel full
    /// of phantom sessions.
    @discardableResult
    func reportUnlessClassified(_ id: SessionID, at now: Date) -> Bool {
        guard watched[id]?.reported == nil else { return false }
        return report(.working, for: id, at: now)
    }
}
