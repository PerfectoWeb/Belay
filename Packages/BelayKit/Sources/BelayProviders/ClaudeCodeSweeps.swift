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
            deadline: .now() + Self.tickInterval,
            repeating: Self.tickInterval,
            leeway: .seconds(1))
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
            report(.idle, for: id, at: now)
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

        for record in tracked {
            guard record.isAlive else {
                end(record.session, at: now)
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
