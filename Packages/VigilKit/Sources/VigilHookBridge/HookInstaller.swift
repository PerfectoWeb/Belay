import Foundation
import VigilSupport

/// Installs and removes Vigil's hooks in `~/.claude/settings.json`.
///
/// Nothing here writes without being asked to: `preview` produces exactly the
/// bytes `install` would land, so the UI can show them and get consent first.
/// The order inside a write is fixed and not negotiable — parse, refuse if it is
/// not plain JSON, merge, back up, then atomically replace. A failure at any
/// step leaves the user's file exactly as it was (docs/11 R2).
public struct HookInstaller: Sendable {
    public struct Preview: Sendable, Equatable {
        /// Pretty-printed JSON of the file as it stands.
        public let current: String
        /// Pretty-printed JSON of what `install` would write.
        public let proposed: String

        public var isChange: Bool { current != proposed }
    }

    public enum Outcome: Sendable, Equatable {
        /// The file already says what we wanted it to say; nothing was written
        /// and no backup was taken.
        case unchanged
        case written(backup: URL?)
    }

    private let document: SettingsDocument

    public init(paths: BridgePaths = .real()) {
        document = SettingsDocument(url: paths.claudeSettings, backups: paths.backups)
    }

    public var settingsURL: URL { document.url }

    public func isInstalled() throws -> Bool {
        try !SettingsMerge.installedURLs(in: document.load()).isEmpty
    }

    public func preview(endpoint: BridgeEndpoint) throws -> Preview {
        let current = try document.load()
        let proposed = try SettingsMerge.merged(current, endpoint: endpoint)
        return Preview(current: try text(current), proposed: try text(proposed))
    }

    @discardableResult
    public func install(endpoint: BridgeEndpoint) throws -> Outcome {
        try apply(endpoint: endpoint)
    }

    @discardableResult
    public func uninstall() throws -> Outcome {
        try apply(endpoint: nil)
    }

    /// Self-heal. The recorded port is ephemeral and the app bundle can move, so
    /// on every launch the installed URL is compared with the live one and
    /// rewritten if it has drifted.
    ///
    /// Deliberately does nothing when Vigil is not installed: a stale record is
    /// worth fixing, but silently adding hooks the user never consented to is
    /// the thing this module exists to avoid.
    @discardableResult
    public func reconcile(endpoint: BridgeEndpoint) throws -> Outcome {
        guard try isInstalled() else { return .unchanged }
        let outcome = try apply(endpoint: endpoint)
        if case .written = outcome {
            Log.bridge.info("Rewrote Claude Code hooks: the recorded receiver URL was stale")
        }
        return outcome
    }

    /// What the user can copy by hand when their settings file is not plain JSON
    /// and Vigil refuses to touch it.
    public static func snippet(for endpoint: BridgeEndpoint) throws -> String {
        let data = try SettingsDocument.serialize(
            ["hooks": HookConfiguration.hooksSection(for: endpoint)])
        return SettingsDocument.text(data)
    }

    private func apply(endpoint: BridgeEndpoint?) throws -> Outcome {
        let current = try document.load()
        let proposed = try SettingsMerge.merged(current, endpoint: endpoint)
        let data = try SettingsDocument.serialize(proposed)
        guard try SettingsDocument.serialize(current) != data else { return .unchanged }

        let backup = try document.backup()
        try document.write(data)
        return .written(backup: backup)
    }

    private func text(_ object: [String: Any]) throws -> String {
        SettingsDocument.text(try SettingsDocument.serialize(object))
    }
}
