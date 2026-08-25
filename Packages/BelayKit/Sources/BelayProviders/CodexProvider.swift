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
        supportsPreciseDetection: true)

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
    /// Whether the provider is currently running, so the app layer can log a
    /// start only when one genuinely happens (a re-`start()` is a silent no-op).
    public var isWatching: Bool { isStarted }

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
        case .noSessionsYet, .notInstalled:
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
        // A coalesced FSEvents batch can be dispatched as a Task that lands
        // after stop(): guard against re-adopting a rollout into a swept watch
        // set with no ticker left to idle it.
        guard isStarted else { return }
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
        return absorb(delta, id: id, now: now)
    }

    /// Reads a delta into a verdict and a report; shared between the watch
    /// loop and the adopt path, which reads its delta up front to check the
    /// record clocks.
    @discardableResult
    func absorb(_ delta: TranscriptDelta, id: SessionID, now: Date) -> Bool {
        guard var watch = watched[id], delta.indicatesWrite else { return false }
        watch.lastWriteAt = now
        if watch.workspace == nil { watch.workspace = CodexRollout.workspace(in: delta.lines) }
        let verdict = CodexRollout.verdict(in: delta.lines)
        // A delta with no marker keeps the flag as it was: growth mid-turn says
        // nothing about whether the turn closed.
        if let verdict { watch.turnOpen = verdict.turnOpen }
        watched[id] = watch
        if let verdict { return report(verdict.activity, for: id, at: now) }
        // Bytes without a marker are evidence of work mid-turn (docs/03, risk
        // R1) — but not a beginning. Housekeeping and token-count records
        // must not flip a quiet session back to Working; a real turn opens
        // with a marker.
        guard watch.reported == .working else { return false }
        return report(.working, for: id, at: now)
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
        // A session whose first word is "idle" is not news — it is the Codex
        // app touching old rollouts as it opens, dozens at a time, and every
        // one of them would otherwise appear in the panel as a row that never
        // did anything. Record the state, follow the file, say nothing; the
        // first *working* still announces the session normally.
        if activity == .idle, watch.reported == nil {
            watch.reported = .idle
            watched[id] = watch
            return false
        }
        if activity != watch.reported {
            let was = watch.reported.map(String.init(describing:)) ?? "new"
            EventLog.note(
                "codex session \(id) \(was)->\(activity) turnOpen=\(watch.turnOpen ? 1 : 0)")
        }
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
