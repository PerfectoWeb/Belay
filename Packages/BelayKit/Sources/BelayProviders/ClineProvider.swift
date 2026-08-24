import BelayCore
import BelaySupport
import Foundation

/// Tier A detection for the Cline CLI, built on its session state files.
///
/// Cline is the plainest of the three: every session keeps an explicit
/// `status` field in its own small JSON file, updated as the run moves
/// through `running` to `completed`/`cancelled`/`failed`, with `idle` for an
/// interactive session waiting on its person. FSEvents says a session
/// changed; the status is re-read; the sibling messages file's growth is the
/// heartbeat. One caveat is load-bearing: a Ctrl-C leaves the status stuck on
/// `running` forever (verified live, 2026-08-24), so the idle sweep — not the
/// status — has the last word on silence.
public actor ClineProvider: ActivityProvider {

    nonisolated public let descriptor = ProviderDescriptor(
        id: .cline,
        displayName: "Cline",
        summary: String(
            localized: "Watches Cline's session files to tell when a task is running.",
            bundle: .main),
        symbolName: "terminal",
        supportsPreciseDetection: false)

    public let signals: AsyncStream<ActivitySignal>

    let configuration: Configuration
    let access: FileAccessProvider
    let clock: any Clock
    private let continuation: AsyncStream<ActivitySignal>.Continuation
    let queue = DispatchQueue(label: "com.perfectoweb.belay.providers.cline", qos: .utility)

    var watched: [SessionID: ClineWatch] = [:]
    private var events: FileEventStream?
    var ticker: DispatchSourceTimer?
    private var isStarted = false

    public init(
        configuration: Configuration = .clineHome(),
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
        isStarted = false
    }

    // MARK: - Watching

    func handle(changedPaths paths: [String]) {
        let now = clock.now
        let ids = Set(
            paths.compactMap {
                ClineSessions.sessionID(of: $0, under: configuration.sessionsDirectory)
            })
        for id in ids { ingest(id, now: now) }
    }

    @discardableResult
    func ingest(_ id: String, now: Date) -> Bool {
        let stateURL = ClineSessions.stateURL(id: id, under: configuration.sessionsDirectory)
        guard let state = ClineSessionState.load(from: stateURL, access: access) else {
            // The state file going away is the session going away.
            if watched[SessionID(id)] != nil { end(SessionID(id), at: now, cause: "state-gone") }
            return false
        }
        guard var watch = watched[SessionID(id)] else {
            return adopt(state, stateURL: stateURL, now: now, atStartup: false)
        }
        let messages = FileSnapshot(url: watch.messagesURL)
        if let messages, messages.size > watch.messagesBytes {
            watch.messagesBytes = messages.size
            watch.lastWriteAt = now
        }
        if watch.workspace == nil { watch.workspace = state.workspace }
        watched[watch.id] = watch
        guard let status = state.knownStatus else { return false }
        if status.activity == .ended {
            end(watch.id, at: now, cause: state.status)
            return true
        }
        return report(status.activity, for: watch.id, at: now)
    }

    @discardableResult
    func adopt(_ state: ClineSessionState, stateURL: URL, now: Date, atStartup: Bool) -> Bool {
        guard let snapshot = FileSnapshot(url: stateURL) else { return false }
        // A session that is already over is history, not news — at startup or
        // at runtime, where Codex Desktop's importer materialises other
        // agents' old conversations wholesale.
        guard let status = state.knownStatus, status.activity != .ended else { return false }
        var watch = ClineWatch(
            id: SessionID(state.sessionID.isEmpty ? stateURL.lastPathComponent : state.sessionID),
            stateURL: stateURL,
            workspace: state.workspace,
            lastWriteAt: atStartup ? snapshot.modified : now,
            messagesBytes: 0,
            reported: nil)
        watch.messagesBytes = FileSnapshot(url: watch.messagesURL)?.size ?? 0

        if atStartup {
            let age = now.timeIntervalSince(snapshot.modified)
            guard age <= configuration.staleAtStartupAfter else { return false }
            watched[watch.id] = watch
            // Announce only a live turn; a merely-followed session speaks
            // when it next moves. A stuck `running` from a Ctrl-C is old by
            // now and stays silent until the sweep or a real write.
            guard status == .running, age <= configuration.inferredIdleAfter else { return false }
            EventLog.note("cline session start \(watch.id) ws=\(watch.workspace ?? "?")")
            return report(.working, for: watch.id, at: now)
        }

        watched[watch.id] = watch
        EventLog.note("cline session start \(watch.id) ws=\(watch.workspace ?? "?")")
        return report(status.activity, for: watch.id, at: now)
    }

    func seedExistingSessions() {
        let now = clock.now
        for id in ClineSessions.sessionIDs(under: configuration.sessionsDirectory, access: access) {
            let stateURL = ClineSessions.stateURL(id: id, under: configuration.sessionsDirectory)
            guard let state = ClineSessionState.load(from: stateURL, access: access) else { continue }
            adopt(state, stateURL: stateURL, now: now, atStartup: true)
        }
    }

    // MARK: - Emitting

    @discardableResult
    func report(_ activity: SessionActivity, for id: SessionID, at now: Date) -> Bool {
        guard var watch = watched[id] else { return false }
        guard activity == .working || activity != watch.reported else { return false }
        // A session whose first word is "idle" is an interactive CLI waiting
        // for its person, not news; the first *working* announces normally.
        if activity == .idle, watch.reported == nil {
            watch.reported = .idle
            watched[id] = watch
            return false
        }
        if activity != watch.reported {
            let was = watch.reported.map(String.init(describing:)) ?? "new"
            EventLog.note("cline session \(id) \(was)->\(activity)")
        }
        watch.reported = activity
        watch.lastWriteAt = now
        watch.announced = true
        watched[id] = watch
        yield(activity, from: watch, at: now)
        return true
    }

    func end(_ id: SessionID, at now: Date, cause: String) {
        guard let watch = watched.removeValue(forKey: id) else { return }
        // A session that was never announced ends unannounced.
        guard watch.announced else { return }
        EventLog.note("cline session end \(id) cause=\(cause)")
        yield(.ended, from: watch, at: now)
    }

    private func yield(_ activity: SessionActivity, from watch: ClineWatch, at now: Date) {
        continuation.yield(
            ActivitySignal(
                provider: .cline,
                session: watch.id,
                activity: activity,
                workspace: watch.workspace,
                timestamp: now,
                confidence: .inferred))
    }
}
