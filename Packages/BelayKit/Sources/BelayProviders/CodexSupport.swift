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
        case noSessionsYet
        case noAccess
    }

    var reach: Reach {
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
            Task { await self.sweepForIdle(now: self.clock.now) }
        }
        timer.setEventHandler(handler: tick)
        timer.resume()
        ticker = timer
    }

    func sweepForIdle(now: Date) {
        for (id, watch) in watched where watch.reported == .working {
            let silence = now.timeIntervalSince(watch.lastWriteAt)
            guard silence > configuration.inferredIdleAfter else { continue }
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
