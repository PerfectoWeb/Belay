import BelaySupport
import Foundation

/// Installs and removes Belay's hooks in `~/.codex/hooks.json`, and keeps the
/// trust ledger in `config.toml` agreeing with them.
///
/// The Claude installer's discipline, plus one codex-only step: a hook whose
/// hash is not recorded under `hooks.state` in `config.toml` is *silently
/// skipped*, so writing hooks.json without writing trust installs nothing.
/// The hashes are not computable here — they come from `codex app-server`'s
/// `hooks/list`, injected as a closure so tests never spawn a process.
public struct CodexHookInstaller: Sendable {
    public typealias ListHooks = @Sendable () throws -> [CodexListedHook]

    public enum Outcome: Sendable, Equatable {
        case unchanged
        case written(backup: URL?)
    }

    private let document: SettingsDocument
    private let config: CodexConfigDocument
    private let listHooks: ListHooks

    public init(paths: BridgePaths = .real(), listHooks: ListHooks? = nil) {
        document = SettingsDocument(
            url: paths.codexHooks, backups: paths.backups, prefix: "codex-hooks")
        config = CodexConfigDocument(url: paths.codexConfig, backups: paths.backups)
        let home = paths.codexHome
        self.listHooks =
            listHooks ?? {
                guard let binary = CodexAppServer.locateBinary() else {
                    throw BridgeError.codexUnavailable("no codex binary was found")
                }
                return try CodexAppServer.listHooks(binary: binary, codexHome: home)
            }
    }

    public var hooksURL: URL { document.url }

    public func isInstalled() throws -> Bool {
        try !SettingsMerge.installedURLs(in: document.load(), vocabulary: CodexHookVocabulary.self)
            .isEmpty
    }

    /// Pretty-printed before and after of `hooks.json`, for the consent sheet.
    /// The trust tables are described, not diffed: their exact hashes do not
    /// exist until the hooks do.
    public func preview(endpoint: BridgeEndpoint) throws -> HookInstaller.Preview {
        let current = try document.load()
        let proposed = try SettingsMerge.merged(
            current, endpoint: endpoint, vocabulary: CodexHookVocabulary.self)
        return HookInstaller.Preview(
            current: SettingsDocument.text(try SettingsDocument.serialize(current)),
            proposed: SettingsDocument.text(try SettingsDocument.serialize(proposed)))
    }

    /// Merge, then trust. The order matters: `hooks/list` reports what the
    /// file says *now*, so the file goes first and the ledger follows. A
    /// failure in the trust step leaves hooks installed but inert — reported,
    /// not hidden, because "installed and silently dead" is codex's default
    /// and the whole reason this step exists.
    @discardableResult
    public func install(endpoint: BridgeEndpoint) throws -> Outcome {
        let outcome = try apply(endpoint: endpoint)
        try trustOwnHooks()
        return outcome
    }

    @discardableResult
    public func uninstall() throws -> Outcome {
        // The keys must be computed while the file still names our groups;
        // after the strip their positions are gone.
        let keys = try ownTrustKeys()
        let outcome = try apply(endpoint: nil)
        if !keys.isEmpty {
            let text = try config.load()
            let cleaned = CodexConfigDocument.removingTrust(text, keys: keys)
            if cleaned != text {
                try config.backup()
                try config.write(cleaned)
            }
        }
        return outcome
    }

    /// Self-heal for a moved port: rewrite and re-trust, only when installed.
    @discardableResult
    public func reconcile(endpoint: BridgeEndpoint) throws -> Outcome {
        guard try isInstalled() else { return .unchanged }
        let expected = CodexHookConfiguration.url(port: endpoint.port)
        let current = SettingsMerge.installedURLs(
            in: try document.load(), vocabulary: CodexHookVocabulary.self)
        guard current.contains(where: { $0 != expected }) else { return .unchanged }
        let outcome = try install(endpoint: endpoint)
        if case .written = outcome {
            Log.bridge.info("Rewrote Codex hooks: the recorded receiver URL was stale")
        }
        return outcome
    }

    // MARK: - Steps

    private func apply(endpoint: BridgeEndpoint?) throws -> Outcome {
        let current = try document.load()
        let proposed = try SettingsMerge.merged(
            current, endpoint: endpoint, vocabulary: CodexHookVocabulary.self)
        let data = try SettingsDocument.serialize(proposed)
        guard try SettingsDocument.serialize(current) != data else { return .unchanged }
        let backup = try document.backup()
        try document.write(data)
        return .written(backup: backup)
    }

    /// Writes `trusted_hash` tables for exactly the hooks that are ours: same
    /// source file, marker in the command. A user's own hook in the same file
    /// is never touched — trusting someone else's hook is not Belay's call.
    private func trustOwnHooks() throws {
        let listed = try listHooks()
        let ours = listed.filter {
            $0.sourcePath == document.url.path && $0.key.hasPrefix(document.url.path + ":")
                && !$0.currentHash.isEmpty
        }
        let wanted = try ownTrustKeys()
        let entries = ours.filter { wanted.contains($0.key) }
            .map { (key: $0.key, hash: $0.currentHash) }
        guard !entries.isEmpty else {
            throw BridgeError.codexUnavailable("codex reported none of Belay's hooks back")
        }
        let text = try config.load()
        let updated = CodexConfigDocument.addingTrust(text, entries: entries)
        guard updated != text else { return }
        try config.backup()
        try config.write(updated)
    }

    /// The `hooks.state` keys for Belay's groups, computed from the file:
    /// `<path>:<snake_event>:<groupIndex>:<hookIndex>`, hook index always 0
    /// because Belay writes one entry per group.
    func ownTrustKeys() throws -> [String] {
        let settings = try document.load()
        guard let section = settings["hooks"] as? [String: Any] else { return [] }
        var keys: [String] = []
        for (event, value) in section {
            guard let groups = value as? [Any] else { continue }
            for (index, group) in groups.enumerated() {
                guard let dictionary = group as? [String: Any],
                    let entries = dictionary["hooks"] as? [Any],
                    entries.contains(where: { CodexHookConfiguration.belayURL($0) != nil })
                else { continue }
                keys.append(
                    "\(document.url.path):\(CodexHookConfiguration.snakeCase(event)):\(index):0")
            }
        }
        return keys.sorted()
    }
}
