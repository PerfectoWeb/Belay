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
        case .noProjectsYet:
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
            end(id, at: now, cause: "transcript-gone")
            return true
        }
        let delta = watch.cursor.read(using: access)
        watched[id] = watch
        guard delta.indicatesWrite else { return false }
        watch.lastWriteAt = now
        let verdict = TranscriptClassifier.verdict(in: delta.lines)
        // A delta with no conversational record keeps the flag as it was: the
        // metadata says nothing about whose move it is.
        if let verdict { watch.awaitingAssistant = verdict.awaitingAssistant }
        watched[id] = watch
        // No conversational record in the delta still means bytes arrived, and
        // bytes arriving is itself the signal (docs/03, risk R1).
        return report(verdict?.activity ?? .working, for: id, at: now)
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
            return ingest(url, now: now) || report(.working, for: id, at: now)
        }

        // A transcript that appears while we are running is news, so pick up the
        // tail rather than EOF — that classifies the turn immediately instead of
        // waiting for the next append.
        watch.cursor.seed(.tailWindow, snapshot: snapshot)
        watched[id] = watch
        EventLog.note("session start \(id) ws=\(watch.workspace ?? "?")")
        return ingest(url, now: now) || report(.working, for: id, at: now)
    }

    func seedExistingTranscripts() {
        let now = clock.now
        let found = TranscriptWatch.transcripts(under: configuration.projectsDirectory, access: access)
        for transcript in found {
            adopt(transcript, id: TranscriptWatch.sessionID(for: transcript), now: now, atStartup: true)
        }
    }

    // MARK: - Emitting

    @discardableResult
    func report(_ activity: SessionActivity, for id: SessionID, at now: Date) -> Bool {
        guard var watch = watched[id] else { return false }
        // `.working` repeats deliberately: the coordinator treats it as a
        // heartbeat and needs a fresh timestamp. `.idle` repeating is just noise.
        guard activity == .working || activity != watch.reported else { return false }
        watch.reported = activity
        watched[id] = watch
        yield(activity, from: watch, at: now)
        return true
    }

    func end(_ id: SessionID, at now: Date, cause: String) {
        guard let watch = watched.removeValue(forKey: id) else { return }
        EventLog.note("session end \(id) cause=\(cause)")
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
                name: watch.name,
                timestamp: now,
                confidence: .inferred))
    }
}
