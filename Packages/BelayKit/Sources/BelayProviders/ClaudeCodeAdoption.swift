import BelayCore
import BelaySupport
import Foundation

/// How a transcript becomes a watch: found at startup, or appearing while
/// Belay runs. Beside the provider for the file-length rule.
extension ClaudeCodeProvider {
    @discardableResult
    func adopt(_ url: URL, id: SessionID, now: Date, atStartup: Bool) -> Bool {
        guard TranscriptLocation.isAgentTranscript(url), let snapshot = FileSnapshot(url: url) else {
            return false
        }
        var watch = TranscriptWatch(
            adopting: url, id: id, at: atStartup ? snapshot.modified : now, access: access)

        guard !atStartup else {
            // 45 transcripts live on this machine (docs/DISCOVERY §1), so launch
            // is where "Belay discovered forty sessions and pinned the Mac awake"
            // happens. Anything stale is not followed; anything merely old is
            // followed but silent until it actually moves.
            let age = now.timeIntervalSince(snapshot.modified)
            guard age <= configuration.staleAtStartupAfter else { return false }
            guard age <= configuration.inferredIdleAfter else {
                watch.cursor.seed(.endOfFile, snapshot: snapshot)
                watched[id] = watch
                return false
            }
            // Fresh enough to be a live turn — so classify its tail rather
            // than assume one. Assuming reported `.working` blind, which was
            // almost right and wrong twice over: a turn that had just
            // finished was held for nothing, and a session Belay opened onto
            // mid-retry started with its awaiting flag down and decayed at
            // the short horizon instead of getting the grace.
            watch.cursor.seed(.tailWindow, snapshot: snapshot)
            watched[id] = watch
            return ingest(url, now: now) || reportUnlessClassified(id, at: now)
        }

        // A transcript that appears while we are running is usually news, so
        // pick up the tail rather than EOF — that classifies the turn
        // immediately instead of waiting for the next append.
        //
        // Usually. The file's appearance is the file system's word, not the
        // agent's: Codex's session importer, backups and indexers bump mtimes
        // on transcripts that have not spoken for weeks, and one such sweep
        // of `~/.claude` raised thirty month-old subagents as Working rows in
        // a single second (2026-08-24, ws=pdd). The records carry their own
        // clocks, which nothing outside the CLI can touch — so a tail whose
        // newest record is old opens nothing, and the file is followed
        // silently from its end, exactly like the stale case at startup.
        watch.cursor.seed(.tailWindow, snapshot: snapshot)
        let delta = watch.cursor.read(using: access)
        let newest = TranscriptClassifier.newestTimestamp(in: delta.lines)
        if let newest, now.timeIntervalSince(newest) > configuration.staleAtStartupAfter {
            if let current = FileSnapshot(url: url) {
                watch.cursor.seed(.endOfFile, snapshot: current)
            }
            watched[id] = watch
            EventLog.note("session stale-touch \(id) ws=\(watch.workspace ?? "?")")
            return false
        }
        watched[id] = watch
        EventLog.note("session start \(id) ws=\(watch.workspace ?? "?")")
        return absorb(delta, id: id, now: now) || reportUnlessClassified(id, at: now)
    }

    /// The adopt fallback: bytes arrived but the tail carried no verdict, so
    /// call it working. A tail that was classified — even into a silent first
    /// idle — already had its say; forcing `.working` over it is how touched
    /// old transcripts become phantom rows.
    @discardableResult
    func reportUnlessClassified(_ id: SessionID, at now: Date) -> Bool {
        guard watched[id]?.reported == nil else { return false }
        return report(.working, for: id, at: now)
    }

    func seedExistingTranscripts() {
        let now = clock.now
        let found = TranscriptWatch.transcripts(under: configuration.projectsDirectory, access: access)
        for transcript in found {
            adopt(transcript, id: TranscriptWatch.sessionID(for: transcript), now: now, atStartup: true)
        }
    }

}
