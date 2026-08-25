import BelayCore
import BelaySupport
import Foundation

/// The 5 s sweep — everything a file watcher cannot see. See the provider.
///
/// It lives beside `ClaudeCodeProvider` rather than inside it for one dull
/// reason: that file is at the length the linter allows.
extension ClaudeCodeProvider {
    func startTicking() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + configuration.tickInterval,
            repeating: configuration.tickInterval,
            leeway: .milliseconds(Int(configuration.tickInterval * 200)))
        // See `PowerSourceMonitor.start()` for why this is hoisted.
        let tick: @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            Task { await self.tick() }
        }
        timer.setEventHandler(handler: tick)
        timer.resume()
        ticker = timer
    }

    func tick() {
        let now = clock.now
        sweepForIdle(now: now)
        tickCount += 1
        guard tickCount.isMultiple(of: 3) else { return }
        sweepForDeadProcesses(now: now)
    }

    func sweepForIdle(now: Date) {
        for (id, watch) in watched where watch.reported == .working {
            // `lastEvidenceAt`, not `lastWriteAt`: a running tool call writes
            // nothing, and Tier C's proof of one has to count or this sweep
            // undoes it five seconds later.
            let silence = now.timeIntervalSince(watch.lastEvidenceAt)
            guard silence > configuration.inferredIdleAfter else { continue }
            // One more look at the file before any verdict on the silence.
            // The closing records can land right after a delta was read, and
            // FSEvents coalesces that tail into the event already handled —
            // leaving a finished turn looking open and riding the fifteen-
            // minute grace toward a false "went quiet". A no-change read
            // costs a stat; an unread ending costs a wrong sentence.
            if ingest(watch.url, now: now) { continue }
            // A turn waiting on the API is silent by nature — a retry loop
            // writes nothing for minutes — so it gets the longer horizon. The
            // repeated `.working` is deliberate: the coordinator's session TTL
            // is shorter than this grace, and without a heartbeat the ledger
            // would evict the session mid-retry. A dead CLI does not get the
            // grace; Tier C ends its session within a sweep or two.
            if watch.awaitingAssistant, silence <= configuration.awaitingAssistantGrace {
                report(.working, for: id, at: now)
                continue
            }
            if watch.awaitingAssistant {
                // The grace ran out with the answer still owed. That is not a
                // finished turn — it is a run that stopped without finishing
                // (a retry that never came back, or a prompt abandoned at the
                // keyboard), so the session ends rather than idles: ending is
                // what makes the app say "went quiet" instead of "finished",
                // which was the wrong sentence for this moment. A transcript
                // that wakes up later is simply adopted as a fresh session.
                end(id, at: now, cause: "awaiting-grace-expired")
                continue
            }
            if report(.idle, for: id, at: now) {
                EventLog.note("session idle \(id) silence=\(Int(silence))s")
            }
        }
    }

    /// Tier C: reap dead sessions; keep quiet-but-working ones alive.
    func sweepForDeadProcesses(
        now: Date,
        isAlive: @Sendable (pid_t) -> Bool = ProcessPresence.isAlive,
        busyPids: @Sendable (Set<pid_t>, TimeInterval, Date) -> Set<pid_t>? = AgentChildren.busy
    ) {
        let records = ProcessPresence.scan(
            directory: configuration.sessionsDirectory, access: access, isAlive: isAlive)
        // Only followed sessions can pin the Mac awake; stale files are noise.
        let tracked = records.filter { watched[$0.session] != nil }
        // `nil` means the process table could not be read, which is "ask again
        // later" and never "nothing is running" — collapsing it to an empty set
        // would drop the assertion mid-turn on a transient sysctl failure.
        //
        // The horizon is the same one Tier A idles on: past it, a surviving
        // child is a background process, not a running tool call. See
        // `AgentChildren` for why an unbounded "has a child" pins the Mac awake.
        let busy = busyPids(
            Set(tracked.filter(\.isAlive).map(\.pid)), configuration.inferredIdleAfter, now)
        // A session can have more than one sidecar: a crash leaves
        // `sessions/<oldpid>.json` behind, and resuming the same session writes
        // `sessions/<newpid>.json` beside it. Ending on the dead record would
        // kill the live session the new pid is keeping — and during an
        // awaiting-assistant silence (a 529 retry loop) there is no transcript
        // write to re-adopt from, so the Mac would sleep mid-retry. A session is
        // dead only when no sidecar for it is alive.
        let aliveSessions = Set(tracked.filter(\.isAlive).map(\.session))

        for record in tracked {
            guard record.isAlive else {
                if !aliveSessions.contains(record.session) {
                    end(record.session, at: now, cause: "process-dead")
                }
                continue
            }
            if let workspace = record.workspace {
                watched[record.session]?.workspace = workspace
            }
            // The session name, which is the only thing telling two
            // sessions in one checkout apart in the panel.
            watched[record.session]?.name = record.name
            // A freshly started child means a tool is running (risk R6).
            if busy?.contains(record.pid) == true {
                watched[record.session]?.lastBusyChildAt = now
                report(.working, for: record.session, at: now)
            }
        }
    }
}
