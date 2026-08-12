import Foundation

extension ClaudeCodeProvider {
    public struct Configuration: Sendable {
        public var projectsDirectory: URL
        public var sessionsDirectory: URL
        /// No growth for this long ends the turn. docs/DISCOVERY §2.2 caught a
        /// real 10 s silence inside one tool call, so this must not be tightened.
        public var inferredIdleAfter: TimeInterval
        /// A transcript untouched for longer than this at launch is history.
        public var staleAtStartupAfter: TimeInterval
        public var latency: TimeInterval

        public init(
            projectsDirectory: URL,
            sessionsDirectory: URL,
            inferredIdleAfter: TimeInterval = 45,
            staleAtStartupAfter: TimeInterval = 600,
            latency: TimeInterval = 1.0
        ) {
            self.projectsDirectory = projectsDirectory
            self.sessionsDirectory = sessionsDirectory
            self.inferredIdleAfter = inferredIdleAfter
            self.staleAtStartupAfter = staleAtStartupAfter
            self.latency = latency
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
