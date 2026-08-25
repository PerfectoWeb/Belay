import BelaySupport
import Foundation

/// Installs and removes Belay's hook scripts in `~/.cline/hooks`.
///
/// Different medium, same discipline as the other two installers: preview is
/// exactly what install writes, nothing foreign is ever touched, and every
/// step either completes or changes nothing. The medium is simpler — one
/// small script file per event, recognised by its marker line — so there is
/// no merge and no backup dance: Belay's own files are the only ones it
/// writes, and a foreign file under a name Belay wants is skipped, reported,
/// and left exactly where it stands.
public struct ClineHookInstaller: Sendable {
    public enum Outcome: Sendable, Equatable {
        case unchanged
        case written
    }

    private let hooks: URL

    public init(paths: BridgePaths = .real()) {
        hooks = paths.clineHooks
    }

    public var hooksURL: URL { hooks }

    public func isInstalled() -> Bool {
        ClineHookEvent.allCases.contains {
            content(for: $0).map(ClineHookConfiguration.isBelayScript) == true
        }
    }

    /// The events whose file name is taken by somebody else's script. Shown
    /// in the consent sheet; those events are skipped, not clobbered.
    public func occupied() -> [String] {
        ClineHookEvent.allCases.compactMap { event in
            // A file that exists but will not decode is somebody else's (a
            // Latin-1 script, a binary) and must count as taken: `content`
            // returns nil for both "absent" and "unreadable", so the disk is
            // the tiebreaker.
            let unreadable =
                FileManager.default.fileExists(atPath: url(for: event).path)
                && content(for: event) == nil
            if unreadable { return ClineHookConfiguration.fileName(for: event) }
            guard let existing = content(for: event),
                !ClineHookConfiguration.isBelayScript(existing)
            else { return nil }
            return ClineHookConfiguration.fileName(for: event)
        }
    }

    /// One representative script, for the consent sheet: every file differs
    /// only in the event spelled into its URL.
    public func preview(endpoint: BridgeEndpoint) -> String {
        ClineHookConfiguration.script(for: endpoint, event: .taskStart)
    }

    @discardableResult
    public func install(endpoint: BridgeEndpoint) throws -> Outcome {
        try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        var wrote = false
        for event in ClineHookEvent.allCases {
            let text = ClineHookConfiguration.script(for: endpoint, event: event)
            if let existing = content(for: event) {
                guard ClineHookConfiguration.isBelayScript(existing) else { continue }
                guard existing != text else { continue }
            } else if FileManager.default.fileExists(atPath: url(for: event).path) {
                // Exists but did not decode: a foreign file we must not
                // clobber. `content` cannot tell it from "absent", so this is
                // the one place the two are distinguished before a write.
                continue
            }
            do {
                try Data(text.utf8).write(to: url(for: event))
                // Executable, in case Cline ever runs the hook file directly
                // rather than through a shell. Harmless if it uses a shell (the
                // shebang wins either way), and cheap insurance against a silent
                // "hook never fires" if it does not.
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: url(for: event).path)
            } catch {
                throw BridgeError.settingsWriteFailed(error.localizedDescription)
            }
            wrote = true
        }
        return wrote ? .written : .unchanged
    }

    @discardableResult
    public func uninstall() -> Outcome {
        var removed = false
        for event in ClineHookEvent.allCases {
            guard let existing = content(for: event),
                ClineHookConfiguration.isBelayScript(existing)
            else { continue }
            try? FileManager.default.removeItem(at: url(for: event))
            removed = true
        }
        return removed ? .written : .unchanged
    }

    /// Self-heal for a moved port: rewrite, only when installed and stale.
    @discardableResult
    public func reconcile(endpoint: BridgeEndpoint) throws -> Outcome {
        guard isInstalled() else { return .unchanged }
        let stale = ClineHookEvent.allCases.contains { event in
            guard let existing = content(for: event),
                ClineHookConfiguration.isBelayScript(existing)
            else { return false }
            return ClineHookConfiguration.installedURL(in: existing)
                != ClineHookConfiguration.url(port: endpoint.port, event: event)
        }
        guard stale else { return .unchanged }
        let outcome = try install(endpoint: endpoint)
        if outcome == .written {
            Log.bridge.info("Rewrote Cline hooks: the recorded receiver URL was stale")
        }
        return outcome
    }

    private func url(for event: ClineHookEvent) -> URL {
        hooks.appendingPathComponent(ClineHookConfiguration.fileName(for: event))
    }

    private func content(for event: ClineHookEvent) -> String? {
        try? String(contentsOf: url(for: event), encoding: .utf8)
    }
}
