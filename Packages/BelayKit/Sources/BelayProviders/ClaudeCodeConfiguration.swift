import Foundation

extension ClaudeCodeProvider {
    public struct Configuration: Sendable {
        public var projectsDirectory: URL
        public var sessionsDirectory: URL
        /// No growth for this long ends the turn. docs/DISCOVERY §2.2 caught a
        /// real 10 s silence inside one tool call, so this must not be tightened.
        public var inferredIdleAfter: TimeInterval
        /// The longer horizon for a turn still waiting on the API. A retry loop
        /// writes nothing — 3½ to 5½ minutes between 529 records on this
        /// machine — and that is the moment the run most needs the Mac awake:
        /// work resumes the instant the API answers. Fifteen minutes, the same
        /// budget `awaitingUser` gets, and bounded for the same reason: past it
        /// Belay is guessing, not observing. docs/DISCOVERY §2.3.
        public var awaitingAssistantGrace: TimeInterval
        /// A transcript untouched for longer than this at launch is history.
        public var staleAtStartupAfter: TimeInterval
        public var latency: TimeInterval
        /// Idle inference resolution. Tier C runs every third tick, i.e. 15 s at
        /// the default. Also the heartbeat cadence during the awaiting grace, so
        /// it must stay well under the coordinator's session TTL. Configurable
        /// for the integration suite, which scales the whole pipeline down.
        public var tickInterval: TimeInterval

        public init(
            projectsDirectory: URL,
            sessionsDirectory: URL,
            inferredIdleAfter: TimeInterval = 45,
            awaitingAssistantGrace: TimeInterval = 15 * 60,
            staleAtStartupAfter: TimeInterval = 600,
            latency: TimeInterval = 1.0,
            tickInterval: TimeInterval = 5
        ) {
            self.projectsDirectory = projectsDirectory
            self.sessionsDirectory = sessionsDirectory
            self.inferredIdleAfter = inferredIdleAfter
            self.awaitingAssistantGrace = awaitingAssistantGrace
            self.staleAtStartupAfter = staleAtStartupAfter
            self.latency = latency
            self.tickInterval = tickInterval
        }

        public static func claudeHome(
            _ home: URL = FileManager.default.homeDirectoryForCurrentUser
        ) -> Configuration {
            let root = home.appendingPathComponent(".claude", isDirectory: true)
            return Configuration(
                projectsDirectory: root.appendingPathComponent("projects", isDirectory: true),
                sessionsDirectory: root.appendingPathComponent("sessions", isDirectory: true))
        }
    }
}
