import BelayCore
import BelaySupport
import Foundation

extension CodexProvider {
    public struct Configuration: Sendable {
        public var sessionsDirectory: URL
        /// Same horizons as Claude Code, for the same reasons: a tool call can
        /// be silent for ten seconds, and a turn waiting out a retry can be
        /// silent for minutes at exactly the moment the Mac must stay awake.
        public var inferredIdleAfter: TimeInterval
        public var openTurnGrace: TimeInterval
        public var staleAtStartupAfter: TimeInterval
        public var latency: TimeInterval
        public var tickInterval: TimeInterval

        public init(
            sessionsDirectory: URL,
            inferredIdleAfter: TimeInterval = 45,
            openTurnGrace: TimeInterval = 15 * 60,
            staleAtStartupAfter: TimeInterval = 600,
            latency: TimeInterval = 1.0,
            tickInterval: TimeInterval = 5
        ) {
            self.sessionsDirectory = sessionsDirectory
            self.inferredIdleAfter = inferredIdleAfter
            self.openTurnGrace = openTurnGrace
            self.staleAtStartupAfter = staleAtStartupAfter
            self.latency = latency
            self.tickInterval = tickInterval
        }

        public static func codexHome(
            _ home: URL = FileManager.default.homeDirectoryForCurrentUser
        ) -> Configuration {
            Configuration(
                sessionsDirectory: home.appendingPathComponent(".codex/sessions", isDirectory: true))
        }
    }

    /// How far into `~/.codex` this build can currently see. Mirrors the Claude
    /// Code split: "not used yet" must never be told to grant a folder again.
    enum Reach {
        case ready
        case notInstalled
        case noSessionsYet
        case noAccess
    }

    var reach: Reach {
        if access.isKnownMissing(configuration.sessionsDirectory.deletingLastPathComponent()) {
            return .notInstalled
        }
        if access.hasAccess(to: configuration.sessionsDirectory) { return .ready }
        if access.hasAccess(to: configuration.sessionsDirectory.deletingLastPathComponent()) {
            return .noSessionsYet
        }
        return .noAccess
    }

    public var availability: ProviderAvailability {
        switch reach {
        case .ready:
            return .ready
        case .notInstalled:
            return .unavailable(
                String(localized: "Codex is not installed on this Mac.", bundle: .main))
        case .noSessionsYet:
            return .unavailable(
                String(
                    localized: """
                        Codex has not started a session on this Mac yet. Belay starts \
                        watching by itself when it does.
                        """, bundle: .main))
        case .noAccess:
            return .needsSetup(
                String(
                    localized:
                        "Let Belay read your ~/.codex folder so it can tell when Codex is working.",
                    bundle: .main))
        }
    }

    // MARK: - The 5 s sweep

    func startTicking() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + configuration.tickInterval,
            repeating: configuration.tickInterval,
            leeway: .milliseconds(Int(configuration.tickInterval * 200)))
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
        sweepForDeadProcess(now: now)
    }

    /// Codex has no per-session pid registry the way Claude Code does, but it
    /// has something almost as good: every live session belongs to some `codex`
    /// process. When the table has none at all, a "working" session is a crash
    /// or a quit mid-turn, and fifteen minutes of open-turn grace for a process
    /// that no longer exists is fifteen minutes of a pinned Mac. `nil` from the
    /// roster is a transient read failure and must never end anything.
    func sweepForDeadProcess(now: Date) {
        guard watched.values.contains(where: { $0.reported == .working }) else { return }
        guard let processes = roster() else { return }
        guard !ProcessRoster.contains("codex", in: processes) else { return }
        for (id, watch) in watched where watch.reported == .working {
            end(id, at: now, cause: "process-gone")
        }
    }

    func sweepForIdle(now: Date) {
        for (id, watch) in watched where watch.reported == .working {
            let silence = now.timeIntervalSince(watch.lastWriteAt)
            guard silence > configuration.inferredIdleAfter else { continue }
            // Same re-read Claude Code's sweep does: a closing marker written
            // just after the last delta, coalesced into the handled event,
            // must not leave the turn looking open for the whole grace.
            if ingest(watch.url, now: now) { continue }
            // An open turn is silent by nature while the model retries, so it
            // gets the longer horizon, with heartbeats so the coordinator's
            // session TTL does not evict it mid-retry. Past the grace the
            // answer is still owed: that is a stall, and the session ends as
            // one rather than idling as a finished turn.
            if watch.turnOpen, silence <= configuration.openTurnGrace {
                report(.working, for: id, at: now)
                continue
            }
            if watch.turnOpen {
                end(id, at: now, cause: "turn-grace-expired")
                continue
            }
            if report(.idle, for: id, at: now) {
                EventLog.note("codex session idle \(id) silence=\(Int(silence))s")
            }
        }
    }
}
