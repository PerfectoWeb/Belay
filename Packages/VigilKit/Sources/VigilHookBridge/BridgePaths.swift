import Foundation

/// Where the bridge keeps its own files, and where Claude Code keeps its.
///
/// Everything is derived from one home directory so a test can point the whole
/// module at a temp tree and be certain nothing touches the real `~/.claude`.
public struct BridgePaths: Sendable, Equatable {
    public let support: URL
    public let claudeSettings: URL

    public init(support: URL, claudeSettings: URL) {
        self.support = support
        self.claudeSettings = claudeSettings
    }

    public static func real(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> BridgePaths {
        BridgePaths(
            support: home.appendingPathComponent(
                "Library/Application Support/Vigil", isDirectory: true),
            claudeSettings: home.appendingPathComponent(".claude/settings.json"))
    }

    public var backups: URL { support.appendingPathComponent("backups", isDirectory: true) }
    public var bridgeRecord: URL { support.appendingPathComponent("bridge.json") }
}
