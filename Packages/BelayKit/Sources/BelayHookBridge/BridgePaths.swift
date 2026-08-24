import Foundation

/// Where the bridge keeps its own files, and where the agents keep theirs.
///
/// Everything is derived from one home directory so a test can point the whole
/// module at a temp tree and be certain nothing touches the real `~/.claude`
/// or `~/.codex`.
public struct BridgePaths: Sendable, Equatable {
    public let support: URL
    public let claudeSettings: URL
    public let codexHome: URL

    public init(support: URL, claudeSettings: URL, codexHome: URL) {
        self.support = support
        self.claudeSettings = claudeSettings
        self.codexHome = codexHome
    }

    public static func real(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> BridgePaths {
        BridgePaths(
            support: home.appendingPathComponent(
                "Library/Application Support/Belay", isDirectory: true),
            claudeSettings: home.appendingPathComponent(".claude/settings.json"),
            codexHome: home.appendingPathComponent(".codex", isDirectory: true))
    }

    public var backups: URL { support.appendingPathComponent("backups", isDirectory: true) }
    public var bridgeRecord: URL { support.appendingPathComponent("bridge.json") }
    public var codexHooks: URL { codexHome.appendingPathComponent("hooks.json") }
    public var codexConfig: URL { codexHome.appendingPathComponent("config.toml") }
}
