import BelayCore
import BelaySupport
import Foundation

/// Tier A detection for GitHub Copilot CLI, built on its session event log.
///
/// Copilot streams every session to
/// `~/.copilot/session-state/<uuid>/events.jsonl` with explicit turn markers
/// — `assistant.turn_start` / `assistant.turn_end` — and a `session.shutdown`
/// when it closes, appended as they happen. That is the Codex shape with even
/// less guessing, so this provider is the Codex one with Copilot's spellings:
/// FSEvents says a file changed, `TranscriptCursor` reads the delta,
/// `CopilotEvents` reads the markers, and the 5 s sweep covers the silences.
/// Verified live on copilot-cli 1.0.80 (2026-08-24).
public actor CopilotProvider: ActivityProvider {

    nonisolated public let descriptor = ProviderDescriptor(
        id: .copilot,
        displayName: "Copilot",
        summary: String(
            localized: "Watches Copilot's session events to tell when a turn is running.",
            bundle: .main),
        symbolName: "terminal",
        supportsPreciseDetection: false)

    public let signals: AsyncStream<ActivitySignal>

    let configuration: Configuration
    let access: FileAccessProvider
    let clock: any Clock
    /// Injectable so a test can empty the process table; `nil` from the real
    /// scan means "ask again later", never "gone".
    let roster: @Sendable () -> Set<String>?
    private let continuation: AsyncStream<ActivitySignal>.Continuation
    let queue = DispatchQueue(label: "com.perfectoweb.belay.providers.copilot", qos: .utility)

    var watched: [SessionID: CopilotWatch] = [:]
    private var events: FileEventStream?
    var ticker: DispatchSourceTimer?
    var tickCount = 0
    private var isStarted = false

    public init(
        configuration: Configuration = .copilotHome(),
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
        seedExistingSessions()
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
        // after stop(): guard against re-adopting a session into a swept watch
        // set with no ticker left to idle it.
        guard isStarted else { return }
        let now = clock.now
        for path in Set(paths) {
            let url = URL(fileURLWithPath: path)
            guard CopilotEvents.isEventsFile(url) else { continue }
            ingest(url, now: now)
        }
    }

    @discardableResult
    func ingest(_ url: URL, now: Date) -> Bool {
        let id = CopilotEvents.sessionID(for: url)
        guard var watch = watched[id] else { return adopt(url, id: id, now: now, atStartup: false) }
        guard FileSnapshot(url: watch.url) != nil else {
            end(id, at: now, cause: "events-gone")
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
        if watch.workspace == nil { watch.workspace = CopilotEvents.workspace(in: delta.lines) }
        let verdict = CopilotEvents.verdict(in: delta.lines)
        if let verdict { watch.turnOpen = verdict.turnOpen }
        watched[id] = watch
        // The whole session closing outranks whatever the last turn said.
        if CopilotEvents.sawShutdown(in: delta.lines) {
            end(id, at: now, cause: "shutdown")
            return true
        }
        if let verdict { return report(verdict.activity, for: id, at: now) }
        // Bytes without a marker prolong a turn, never begin one: model
        // checkpoints and usage records must not flip a quiet session back.
        guard watch.reported == .working else { return false }
        return report(.working, for: id, at: now)
    }

    func seedExistingSessions() {
        let now = clock.now
        for id in CopilotEvents.sessionIDs(under: configuration.sessionsDirectory, access: access) {
            let url = CopilotEvents.eventsFile(forSession: id, under: configuration.sessionsDirectory)
            adopt(url, id: SessionID(id), now: now, atStartup: true)
        }
    }

    // MARK: - Emitting

    @discardableResult
    func report(_ activity: SessionActivity, for id: SessionID, at now: Date) -> Bool {
        guard var watch = watched[id] else { return false }
        guard activity == .working || activity != watch.reported else { return false }
        // A session whose first word is "idle" is history being followed, not
        // news; the first *working* announces normally.
        if activity == .idle, watch.reported == nil {
            watch.reported = .idle
            watched[id] = watch
            return false
        }
        if activity != watch.reported {
            let was = watch.reported.map(String.init(describing:)) ?? "new"
            EventLog.note(
                "copilot session \(id) \(was)->\(activity) turnOpen=\(watch.turnOpen ? 1 : 0)")
        }
        watch.reported = activity
        watched[id] = watch
        yield(activity, from: watch, at: now)
        return true
    }

    func end(_ id: SessionID, at now: Date, cause: String) {
        guard let watch = watched.removeValue(forKey: id) else { return }
        EventLog.note("copilot session end \(id) cause=\(cause)")
        guard watch.reported != nil else { return }
        yield(.ended, from: watch, at: now)
    }

    private func yield(_ activity: SessionActivity, from watch: CopilotWatch, at now: Date) {
        continuation.yield(
            ActivitySignal(
                provider: .copilot,
                session: watch.id,
                activity: activity,
                workspace: watch.workspace,
                timestamp: now,
                confidence: .inferred))
    }
}
