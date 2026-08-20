import BelayCore
import BelaySupport
import Foundation

/// Tier A detection for Codex CLI, built on its session rollouts.
///
/// Codex persists explicit turn markers — `task_started` / `task_complete` —
/// into `~/.codex/sessions`, which makes this provider simpler than the Claude
/// Code one: the turn edges are written down rather than inferred from whose
/// record is last. FSEvents says a rollout changed; `TranscriptCursor` reads
/// only the delta; `CodexRollout` reads the markers. A 5 s sweep covers the
/// silence cases. Everything here is `.inferred`; a hook bridge would produce
/// `.exact`, and the markers leave room for one.
public actor CodexProvider: ActivityProvider {

    nonisolated public let descriptor = ProviderDescriptor(
        id: .codex,
        displayName: "Codex",
        summary: String(
            localized: "Watches Codex's session files to tell when a turn is running.",
            bundle: .main),
        symbolName: "terminal",
        supportsPreciseDetection: false)

    public let signals: AsyncStream<ActivitySignal>

    let configuration: Configuration
    let access: FileAccessProvider
    let clock: any Clock
    /// Injectable so a test can empty the process table without asking the
    /// machine's real one to play along. `nil` from the real scan means the
    /// table could not be read, which is "ask again later", never "gone".
    let roster: @Sendable () -> Set<String>?
    private let continuation: AsyncStream<ActivitySignal>.Continuation
    let queue = DispatchQueue(label: "com.perfectoweb.belay.providers.codex", qos: .utility)

    var watched: [SessionID: CodexWatch] = [:]
    private var events: FileEventStream?
    var ticker: DispatchSourceTimer?
    var tickCount = 0
    private var isStarted = false

    public init(
        configuration: Configuration = .codexHome(),
        access: FileAccessProvider = DirectFileAccess(),
        clock: any Clock = SystemClock(),
        roster: (@Sendable () -> Set<String>?)? = nil
    ) {
        self.configuration = configuration
        self.access = access
        self.clock = clock
        self.roster = roster ?? { ProcessRoster.scan() }
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
        case .noSessionsYet:
            throw ProviderError.notInUseYet(path: configuration.sessionsDirectory.path)
        case .noAccess:
            throw ProviderError.accessNotGranted(path: configuration.sessionsDirectory.path)
        }
        seedExistingRollouts()
        events = try FileEventStream(
            root: configuration.sessionsDirectory,
            latency: configuration.latency,
            queue: queue
        ) { [weak self] paths in
            guard let self else { return }
            Task { await self.handle(changedPaths: paths) }
        }
        startTicking()
        isStarted = true
    }

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
        for path in Set(paths) {
            let url = URL(fileURLWithPath: path)
            guard CodexRollout.isRollout(url) else { continue }
            ingest(url, now: now)
        }
    }

    @discardableResult
    func ingest(_ url: URL, now: Date) -> Bool {
        let id = CodexRollout.sessionID(for: url)
        guard var watch = watched[id] else { return adopt(url, id: id, now: now, atStartup: false) }
        guard FileSnapshot(url: watch.url) != nil else {
            end(id, at: now, cause: "rollout-gone")
            return true
        }
        let delta = watch.cursor.read(using: access)
        watched[id] = watch
        guard delta.indicatesWrite else { return false }
        watch.lastWriteAt = now
        if watch.workspace == nil { watch.workspace = CodexRollout.workspace(in: delta.lines) }
        let verdict = CodexRollout.verdict(in: delta.lines)
        // A delta with no marker keeps the flag as it was: growth mid-turn says
        // nothing about whether the turn closed.
        if let verdict { watch.turnOpen = verdict.turnOpen }
        watched[id] = watch
        // Bytes without a marker are still evidence of work (docs/03, risk R1).
        return report(verdict?.activity ?? .working, for: id, at: now)
    }

    @discardableResult
    private func adopt(_ url: URL, id: SessionID, now: Date, atStartup: Bool) -> Bool {
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
            return ingest(url, now: now) || report(.working, for: id, at: now)
        }

        watch.cursor.seed(.tailWindow, snapshot: snapshot)
        watched[id] = watch
        EventLog.note("codex session start \(id) ws=\(watch.workspace ?? "?")")
        return ingest(url, now: now) || report(.working, for: id, at: now)
    }

    func seedExistingRollouts() {
        let now = clock.now
        let found = CodexRollout.rollouts(under: configuration.sessionsDirectory, access: access)
        for rollout in found {
            adopt(rollout, id: CodexRollout.sessionID(for: rollout), now: now, atStartup: true)
        }
    }

    // MARK: - Emitting

    @discardableResult
    func report(_ activity: SessionActivity, for id: SessionID, at now: Date) -> Bool {
        guard var watch = watched[id] else { return false }
        guard activity == .working || activity != watch.reported else { return false }
        watch.reported = activity
        watched[id] = watch
        yield(activity, from: watch, at: now)
        return true
    }

    func end(_ id: SessionID, at now: Date, cause: String) {
        guard let watch = watched.removeValue(forKey: id) else { return }
        EventLog.note("codex session end \(id) cause=\(cause)")
        yield(.ended, from: watch, at: now)
    }

    private func yield(_ activity: SessionActivity, from watch: CodexWatch, at now: Date) {
        continuation.yield(
            ActivitySignal(
                provider: .codex,
                session: watch.id,
                activity: activity,
                workspace: watch.workspace,
                timestamp: now,
                confidence: .inferred))
    }
}
