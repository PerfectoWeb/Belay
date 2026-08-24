import BelayCore
import BelaySupport
import Foundation

/// How an events file becomes a watch: found at startup, or appearing while
/// Belay runs. Beside the provider for the file-length rule, mirroring
/// `CodexAdoption`.
extension CopilotProvider {
    @discardableResult
    func adopt(_ url: URL, id: SessionID, now: Date, atStartup: Bool) -> Bool {
        guard let snapshot = FileSnapshot(url: url) else { return false }
        var watch = CopilotWatch(
            id: id,
            url: url,
            lastWriteAt: atStartup ? snapshot.modified : now,
            workspace: CopilotEvents.workspace(atHeadOf: url, access: access))

        guard !atStartup else {
            // Same launch discipline as the other two: history is not
            // followed, the merely old is followed but silent, and only a file
            // fresh enough to be a live turn gets its tail classified.
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

        // A file that appears or moves while we are running is usually a turn
        // starting. Usually: Codex Desktop's importer taught us that a sync
        // tool can rewrite a month-old session with a fresh mtime. The record
        // clocks cannot be bumped from outside, so an old tail opens nothing
        // and the file is followed silently from its end.
        watch.cursor.seed(.tailWindow, snapshot: snapshot)
        let delta = watch.cursor.read(using: access)
        let newest = CopilotEvents.newestTimestamp(in: delta.lines)
        if let newest, now.timeIntervalSince(newest) > configuration.staleAtStartupAfter {
            if let current = FileSnapshot(url: url) {
                watch.cursor.seed(.endOfFile, snapshot: current)
            }
            watched[id] = watch
            EventLog.note("copilot stale-touch \(id) ws=\(watch.workspace ?? "?")")
            return false
        }
        watched[id] = watch
        EventLog.note("copilot session start \(id) ws=\(watch.workspace ?? "?")")
        return absorb(delta, id: id, now: now) || reportUnlessClassified(id, at: now)
    }

    /// The adopt fallback: bytes arrived but the tail carried no marker, so
    /// call it working. A tail that *was* classified — even into a silent
    /// first idle — already had its say, and forcing `.working` over it is
    /// exactly how a housekeeping pass over old sessions becomes a panel full
    /// of phantoms.
    @discardableResult
    func reportUnlessClassified(_ id: SessionID, at now: Date) -> Bool {
        guard watched[id]?.reported == nil else { return false }
        return report(.working, for: id, at: now)
    }
}
