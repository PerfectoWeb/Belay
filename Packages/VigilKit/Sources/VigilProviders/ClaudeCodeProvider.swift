import Foundation
import VigilCore
import VigilSupport

/// Tier A + Tier C detection for Claude Code.
///
/// FSEvents says a transcript changed; `TranscriptCursor` reads only the delta;
/// `TranscriptClassifier` decides whether the turn is still running. A 5 s sweep
/// covers what a file watcher cannot see: a turn that stopped writing, a process
/// that died mid-record, and work that leaves no trace at all (`AgentChildren`).
///
/// Everything here is `.inferred`. The hook bridge produces `.exact`.
public actor ClaudeCodeProvider: ActivityProvider {
    /// Idle inference resolution. Tier C runs every third tick, i.e. 15 s.
    static let tickInterval: TimeInterval = 5

    nonisolated public let descriptor = ProviderDescriptor(
        id: .claudeCode,
        displayName: "Claude Code",
        summary: "Watches Claude Code's session transcripts to tell when a turn is running.",
        symbolName: "terminal",
        supportsPreciseDetection: true)

    public let signals: AsyncStream<ActivitySignal>

    let configuration: Configuration
    /// Internal so the availability check can live in its own file.
    let access: FileAccessProvider
    private let clock: any Clock
    private let continuation: AsyncStream<ActivitySignal>.Continuation
    private let queue = DispatchQueue(
        label: "com.perfecto-web.vigil.providers.claude-code", qos: .utility)

    private var watched: [SessionID: TranscriptWatch] = [:]
    private var events: FileEventStream?
    private var ticker: DispatchSourceTimer?
    private var tickCount = 0
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
        guard access.hasAccess(to: configuration.projectsDirectory) else {
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
    var isWatching: Bool { events != nil && ticker != nil }

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
            end(id, at: now)
            return true
        }
        let delta = watch.cursor.read(using: access)
        watched[id] = watch
        guard delta.indicatesWrite else { return false }
        watch.lastWriteAt = now
        watched[id] = watch
        // No conversational record in the delta still means bytes arrived, and
        // bytes arriving is itself the signal (docs/03, risk R1).
        return report(TranscriptClassifier.activity(in: delta.lines) ?? .working, for: id, at: now)
    }

    @discardableResult
    private func adopt(_ url: URL, id: SessionID, now: Date, atStartup: Bool) -> Bool {
        guard TranscriptLocation.isAgentTranscript(url), let snapshot = FileSnapshot(url: url) else {
            return false
        }
        var watch = TranscriptWatch(
            adopting: url, id: id, at: atStartup ? snapshot.modified : now, access: access)

        guard !atStartup else {
            // 45 transcripts live on this machine (docs/DISCOVERY §1), so launch
            // is where "Vigil discovered forty sessions and pinned the Mac awake"
            // happens. Anything stale is not followed; anything merely old is
            // followed but silent until it actually moves.
            let age = now.timeIntervalSince(snapshot.modified)
            guard age <= configuration.staleAtStartupAfter else { return false }
            watch.cursor.seed(.endOfFile, snapshot: snapshot)
            watched[id] = watch
            guard age <= configuration.inferredIdleAfter else { return false }
            return report(.working, for: id, at: now)
        }

        // A transcript that appears while we are running is news, so pick up the
        // tail rather than EOF — that classifies the turn immediately instead of
        // waiting for the next append.
        watch.cursor.seed(.tailWindow, snapshot: snapshot)
        watched[id] = watch
        return ingest(url, now: now) || report(.working, for: id, at: now)
    }

    func seedExistingTranscripts() {
        let now = clock.now
        let found = TranscriptWatch.transcripts(under: configuration.projectsDirectory, access: access)
        for transcript in found {
            adopt(transcript, id: TranscriptWatch.sessionID(for: transcript), now: now, atStartup: true)
        }
    }

    // MARK: - Sweeps

    private func startTicking() {
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
            guard now.timeIntervalSince(watch.lastWriteAt) > configuration.inferredIdleAfter else {
                continue
            }
            report(.idle, for: id, at: now)
        }
    }

    /// Tier C: reap dead sessions; keep quiet-but-working ones alive.
    func sweepForDeadProcesses(
        now: Date,
        isAlive: @Sendable (pid_t) -> Bool = ProcessPresence.isAlive,
        busyPids: @Sendable (Set<pid_t>) -> Set<pid_t>? = AgentChildren.busy
    ) {
        let records = ProcessPresence.scan(
            directory: configuration.sessionsDirectory, access: access, isAlive: isAlive)
        // Only followed sessions can pin the Mac awake; stale files are noise.
        let tracked = records.filter { watched[$0.session] != nil }
        // `nil` means the process table could not be read, which is "ask again
        // later" and never "nothing is running" — collapsing it to an empty set
        // would drop the assertion mid-turn on a transient sysctl failure.
        let busy = busyPids(Set(tracked.filter(\.isAlive).map(\.pid)))

        for record in tracked {
            guard record.isAlive else {
                end(record.session, at: now)
                continue
            }
            if let workspace = record.workspace {
                watched[record.session]?.workspace = workspace
            }
            // A live child means a tool is running (risk R6). See AgentChildren.
            if busy?.contains(record.pid) == true {
                report(.working, for: record.session, at: now)
            }
        }
    }

    // MARK: - Emitting

    @discardableResult
    private func report(_ activity: SessionActivity, for id: SessionID, at now: Date) -> Bool {
        guard var watch = watched[id] else { return false }
        // `.working` repeats deliberately: the coordinator treats it as a
        // heartbeat and needs a fresh timestamp. `.idle` repeating is just noise.
        guard activity == .working || activity != watch.reported else { return false }
        watch.reported = activity
        watched[id] = watch
        yield(activity, from: watch, at: now)
        return true
    }

    private func end(_ id: SessionID, at now: Date) {
        guard let watch = watched.removeValue(forKey: id) else { return }
        yield(.ended, from: watch, at: now)
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
                timestamp: now,
                confidence: .inferred))
    }
}
