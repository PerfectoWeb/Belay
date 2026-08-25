import BelayCore
import BelaySupport
import Foundation

extension CopilotProvider {
    public struct Configuration: Sendable {
        public var sessionsDirectory: URL
        /// Same horizons as the other two watchers, for the same reasons: a
        /// tool call can be silent for ten seconds, and a turn waiting out a
        /// retry can be silent for minutes at exactly the moment the Mac must
        /// stay awake.
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

        public static func copilotHome(
            _ home: URL = FileManager.default.homeDirectoryForCurrentUser
        ) -> Configuration {
            Configuration(
                sessionsDirectory: home.appendingPathComponent(
                    ".copilot/session-state", isDirectory: true))
        }
    }

    /// How far into `~/.copilot` this build can currently see. Mirrors the
    /// Codex split: "not used yet" must never be told to grant a folder again.
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
                String(localized: "Copilot is not installed on this Mac.", bundle: .main))
        case .noSessionsYet:
            return .unavailable(
                String(
                    localized: """
                        Copilot has not started a session on this Mac yet. Belay starts \
                        watching by itself when it does.
                        """, bundle: .main))
        case .noAccess:
            return .needsSetup(
                String(
                    localized:
                        "Let Belay read your ~/.copilot folder so it can tell when Copilot is working.",
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

    /// Copilot writes `session.shutdown` on a clean exit, but a Ctrl-C or a
    /// crash mid-turn leaves the last marker at `turn_start` forever. Every
    /// live session belongs to some `copilot` process; when the table has none
    /// at all, a "working" session is a corpse, and fifteen minutes of
    /// open-turn grace for it is fifteen minutes of a pinned Mac. `nil` from
    /// the roster is a transient read failure and must never end anything.
    ///
    /// The Homebrew cask ships a native `copilot` binary, but the npm
    /// distribution can run under `node` or another name — where the absence of
    /// a "copilot" process proves nothing. So the sweep only trusts that
    /// absence once it has actually seen a "copilot" process on this machine;
    /// until then the idle sweep and the shutdown marker do the reaping.
    func sweepForDeadProcess(now: Date) {
        guard watched.values.contains(where: { $0.reported == .working }) else { return }
        guard let processes = roster() else { return }
        if ProcessRoster.contains("copilot", in: processes) {
            sawCopilotProcess = true
            return
        }
        guard sawCopilotProcess else { return }
        for (id, watch) in watched where watch.reported == .working {
            end(id, at: now, cause: "process-gone")
        }
    }

    func sweepForIdle(now: Date) {
        for (id, watch) in watched where watch.reported == .working {
            let silence = now.timeIntervalSince(watch.lastWriteAt)
            guard silence > configuration.inferredIdleAfter else { continue }
            // Same re-read the other sweeps do: a closing marker written just
            // after the last delta, coalesced into the handled event, must not
            // leave the turn looking open for the whole grace.
            if ingest(watch.url, now: now) { continue }
            if watch.turnOpen, silence <= configuration.openTurnGrace {
                report(.working, for: id, at: now)
                continue
            }
            if watch.turnOpen {
                end(id, at: now, cause: "turn-grace-expired")
                continue
            }
            if report(.idle, for: id, at: now) {
                EventLog.note("copilot session idle \(id) silence=\(Int(silence))s")
            }
        }
    }
}
