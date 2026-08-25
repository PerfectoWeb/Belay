import BelayCore
import BelaySupport
import Foundation

extension ClineProvider {
    public struct Configuration: Sendable {
        public var sessionsDirectory: URL
        /// Same silence horizon as the other providers — and here it is also
        /// the safety net: a Ctrl-C leaves a session's status stuck on
        /// `running` with nothing ever writing again (verified live), so
        /// silence has to be allowed to overrule the file.
        public var inferredIdleAfter: TimeInterval
        public var staleAtStartupAfter: TimeInterval
        public var latency: TimeInterval
        public var tickInterval: TimeInterval

        public init(
            sessionsDirectory: URL,
            inferredIdleAfter: TimeInterval = 45,
            staleAtStartupAfter: TimeInterval = 600,
            latency: TimeInterval = 1.0,
            tickInterval: TimeInterval = 5
        ) {
            self.sessionsDirectory = sessionsDirectory
            self.inferredIdleAfter = inferredIdleAfter
            self.staleAtStartupAfter = staleAtStartupAfter
            self.latency = latency
            self.tickInterval = tickInterval
        }

        public static func clineHome(
            _ home: URL = FileManager.default.homeDirectoryForCurrentUser
        ) -> Configuration {
            at(home.appendingPathComponent(".cline", isDirectory: true))
        }

        /// The same layout rooted anywhere — a custom `CLINE_DIR`.
        public static func at(_ root: URL) -> Configuration {
            Configuration(
                sessionsDirectory: root.appendingPathComponent("data/sessions", isDirectory: true))
        }

        /// `~/.cline` itself, for the is-it-installed question: the sessions
        /// folder appears on first use, the home folder on install.
        var clineHome: URL {
            sessionsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        }
    }

    /// How far into `~/.cline` this build can currently see. Mirrors the
    /// Codex split: "not used yet" must never be told to grant a folder again.
    enum Reach {
        case ready
        case notInstalled
        case noSessionsYet
        case noAccess
    }

    var reach: Reach {
        if access.isKnownMissing(configuration.clineHome) { return .notInstalled }
        if access.hasAccess(to: configuration.sessionsDirectory) { return .ready }
        if access.hasAccess(to: configuration.clineHome) { return .noSessionsYet }
        return .noAccess
    }

    public var availability: ProviderAvailability {
        switch reach {
        case .ready:
            return .ready
        case .notInstalled:
            return .unavailable(
                String(localized: "Cline is not installed on this Mac.", bundle: .main))
        case .noSessionsYet:
            return .unavailable(
                String(
                    localized: """
                        Cline has not started a session on this Mac yet. Belay starts \
                        watching by itself when it does.
                        """, bundle: .main))
        case .noAccess:
            return .needsSetup(
                String(
                    localized:
                        "Let Belay read your ~/.cline folder so it can tell when Cline is working.",
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
        sweepForIdle(now: clock.now)
    }

    /// Quiet working sessions go idle: the status file said `running`, but
    /// nothing has been written for the horizon — a stall, or the Ctrl-C
    /// corpse whose status will never change again.
    func sweepForIdle(now: Date) {
        for (id, watch) in watched where watch.reported == .working {
            guard now.timeIntervalSince(watch.lastWriteAt) > configuration.inferredIdleAfter else {
                continue
            }
            EventLog.note("cline session \(id) went quiet")
            report(.idle, for: id, at: now)
        }
    }
}
