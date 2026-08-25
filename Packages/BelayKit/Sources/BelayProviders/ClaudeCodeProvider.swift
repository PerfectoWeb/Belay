import BelayCore
import BelaySupport
import Foundation

/// Tier A + Tier C detection for Claude Code.
///
/// FSEvents says a transcript changed; `TranscriptCursor` reads only the delta;
/// `TranscriptClassifier` decides whether the turn is still running. A 5 s sweep
/// covers what a file watcher cannot see: a turn that stopped writing, a process
/// that died mid-record, and work that leaves no trace at all (`AgentChildren`).
///
/// Everything here is `.inferred`. The hook bridge produces `.exact`.
public actor ClaudeCodeProvider: ActivityProvider {

    nonisolated public let descriptor = ProviderDescriptor(
        id: .claudeCode,
        displayName: "Claude Code",
        summary: String(
            localized: "Watches Claude Code's session transcripts to tell when a turn is running.",
            bundle: .main),
        symbolName: "terminal",
        supportsPreciseDetection: true)

    public let signals: AsyncStream<ActivitySignal>

    let configuration: Configuration
    /// Internal, like the five below it, so the availability check and the
    /// sweeps can live in their own files (this one is at the linter's limit).
    let access: FileAccessProvider
    let clock: any Clock
    private let continuation: AsyncStream<ActivitySignal>.Continuation
    let queue = DispatchQueue(
        label: "com.perfectoweb.belay.providers.claude-code", qos: .utility)

    var watched: [SessionID: TranscriptWatch] = [:]
    private var events: FileEventStream?
    var ticker: DispatchSourceTimer?
    var tickCount = 0
    private var isStarted = false

    public init(
        configuration: Configuration = .claudeHome(),
        access: FileAccessProvider = DirectFileAccess(),
        clock: any Clock = SystemClock()
    ) {
        self.configuration = configuration
        self.access = access
        self.clock = clock
        let made = AsyncStream.makeStream(
            of: ActivitySignal.self, bufferingPolicy: .bufferingNewest(256))
        signals = made.stream
        continuation = made.continuation
    }

    deinit {
        continuation.finish()
    }

    public func start() async throws {
        guard !isStarted else { return }
        switch reach {
        case .ready:
            break
        // Not installed is "not in use yet" for the purposes of starting:
        // nothing to watch, nothing to grant, try again when asked.
        case .noProjectsYet, .notInstalled:
            throw ProviderError.notInUseYet(path: configuration.projectsDirectory.path)
        case .noAccess:
            throw ProviderError.accessNotGranted(path: configuration.projectsDirectory.path)
        }
        seedExistingTranscripts()
        events = try FileEventStream(
            root: configuration.projectsDirectory,
            latency: configuration.latency,
            queue: queue
        ) { [weak self] paths in
            guard let self else { return }
            Task { await self.handle(changedPaths: paths) }
        }
        startTicking()
        isStarted = true
    }

    /// Both halves of the machinery are live. Teardown has to clear both.
    public var isWatching: Bool { events != nil && ticker != nil }

    public func stop() async {
        events?.stop()
        events = nil
        ticker?.cancel()
        ticker = nil
        watched.removeAll()
        tickCount = 0
        isStarted = false
    }

    // MARK: - Watching

    func handle(changedPaths paths: [String]) {
        // A coalesced FSEvents batch can be dispatched as a Task that lands
        // after stop(): without this it would re-adopt a transcript into the
        // just-cleared watch set and yield .working with no ticker left to
        // ever idle it, pinning the Mac until the coordinator's TTL.
        guard isStarted else { return }
        let now = clock.now
        for path in Set(paths) where path.hasSuffix(".jsonl") {
            ingest(URL(fileURLWithPath: path), now: now)
        }
    }

    /// Reads whatever is new in one transcript. Returns whether it yielded a signal.
    @discardableResult
    func ingest(_ url: URL, now: Date) -> Bool {
        let id = TranscriptWatch.sessionID(for: url)
        guard var watch = watched[id] else { return adopt(url, id: id, now: now, atStartup: false) }
        guard FileSnapshot(url: watch.url) != nil else {
            end(id, at: now, cause: "transcript-gone")
            return true
        }
        let delta = watch.cursor.read(using: access)
        watched[id] = watch
        return absorb(delta, id: id, now: now)
    }

    /// What a freshly read delta means, shared by the steady path above and
    /// the adoption of a newly seen file.
    @discardableResult
    func absorb(_ delta: TranscriptDelta, id: SessionID, now: Date) -> Bool {
        guard delta.indicatesWrite, var watch = watched[id] else { return false }
        watch.lastWriteAt = now
        let verdict = TranscriptClassifier.verdict(in: delta.lines)
        // A delta with no conversational record keeps the flag as it was: the
        // metadata says nothing about whose move it is.
        if let verdict { watch.awaitingAssistant = verdict.awaitingAssistant }
        watched[id] = watch
        if let verdict { return report(verdict.activity, for: id, at: now) }
        // No conversational record still means bytes arrived, and mid-turn
        // that is itself the signal (docs/03, risk R1) — an unknown record
        // format must never idle a running turn. But the same bytes are not a
        // beginning: Claude Code writes titles and summaries for a minute or
        // two after a turn closes, and every burst used to flip the idle
        // session back to Working. A real new turn opens with a prompt the
        // classifier can read; until one arrives, quiet sessions stay quiet.
        guard watch.reported == .working else { return false }
        return report(.working, for: id, at: now)
    }

    // MARK: - Emitting

    @discardableResult
    func report(_ activity: SessionActivity, for id: SessionID, at now: Date) -> Bool {
        guard var watch = watched[id] else { return false }
        // `.working` repeats deliberately: the coordinator treats it as a
        // heartbeat and needs a fresh timestamp. `.idle` repeating is just noise.
        guard activity == .working || activity != watch.reported else { return false }
        // A session whose first word is "idle" is not news — it is the app
        // touching old transcripts (a desktop restart rewrites several at
        // once), and each one used to appear as a row that never did
        // anything. Same rule Codex already has: record, follow, say nothing.
        if activity == .idle, watch.reported == nil {
            watch.reported = .idle
            watched[id] = watch
            return false
        }
        // Every state change is a line: the week's panel mysteries were all
        // solved by asking "who said that, and when" — so the log answers it.
        if activity != watch.reported {
            let was = watch.reported.map(String.init(describing:)) ?? "new"
            EventLog.note(
                "session \(id) \(was)->\(activity) awaiting=\(watch.awaitingAssistant ? 1 : 0)")
        }
        watch.reported = activity
        watch.announced = true
        watched[id] = watch
        yield(activity, from: watch, at: now)
        return true
    }

    func end(_ id: SessionID, at now: Date, cause: String) {
        guard let watch = watched.removeValue(forKey: id) else { return }
        EventLog.note("session end \(id) cause=\(cause)")
        // Only a session the UI heard of gets an announced ending — a deleted
        // never-announced transcript leaves no phantom row behind. The cascade
        // still runs regardless, since a child may have been announced.
        if watch.announced { yield(.ended, from: watch, at: now) }
        // A subagent belongs to its parent's process: when Tier C reaps a dead
        // main session, its subagents are dead too, but they never appear in
        // the pid sidecars Tier C reads, so nothing else would ever end them —
        // they would heartbeat `.working` for the full awaiting-assistant grace
        // on a process that is gone. Cline's teammates learned this; Claude's
        // subagents had not. A subagent has no children, so this does not
        // recurse. (`watched` is a value type; removing from `self.watched`
        // inside this loop copies-on-write and leaves the iteration intact.)
        for (childID, child) in watched where child.parent == id {
            end(childID, at: now, cause: "parent-\(cause)")
        }
    }

    private func yield(_ activity: SessionActivity, from watch: TranscriptWatch, at now: Date) {
        continuation.yield(
            ActivitySignal(
                provider: .claudeCode,
                session: watch.id,
                activity: activity,
                workspace: watch.workspace,
                parent: watch.parent,
                kind: watch.kind,
                name: watch.name,
                timestamp: now,
                confidence: .inferred))
    }
}
