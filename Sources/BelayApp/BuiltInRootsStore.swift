import BelayCore
import Foundation

/// Persists the extra folders a built-in agent is watched in, beyond its
/// default home. The agents themselves can relocate — `CLAUDE_CONFIG_DIR`,
/// `CODEX_HOME`, `CLINE_DIR`, `COPILOT_HOME` — and a GUI app cannot read
/// another shell's environment, so the folders arrive by being picked
/// (issue #4). Lives beside `GenericTargetStore` for the same D14 reason.
@MainActor
struct BuiltInRootsStore {
    private let key = "builtInExtraRoots"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func roots(for id: ProviderID) -> [URL] {
        guard let stored = defaults.dictionary(forKey: key) as? [String: [String]] else {
            return []
        }
        return (stored[id.rawValue] ?? []).map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    func add(_ url: URL, for id: ProviderID) {
        var stored = defaults.dictionary(forKey: key) as? [String: [String]] ?? [:]
        var paths = stored[id.rawValue] ?? []
        let path = url.standardizedFileURL.path
        guard !paths.contains(path) else { return }
        paths.append(path)
        stored[id.rawValue] = paths
        defaults.set(stored, forKey: key)
    }

    func remove(path: String, for id: ProviderID) {
        var stored = defaults.dictionary(forKey: key) as? [String: [String]] ?? [:]
        stored[id.rawValue] = (stored[id.rawValue] ?? []).filter { $0 != path }
        if stored[id.rawValue]?.isEmpty == true { stored[id.rawValue] = nil }
        defaults.set(stored, forKey: key)
    }
}

/// What a folder must look like to be one of this agent's homes: the subpath
/// its provider will actually read. Used to validate a pick softly — a wrong
/// folder is warned about, never refused, because the agent may simply not
/// have run there yet.
enum BuiltInRoots {
    static func expectedSubpath(for id: ProviderID) -> String {
        switch id {
        case .codex: return "sessions"
        case .cline: return "data/sessions"
        case .copilot: return "session-state"
        default: return "projects"
        }
    }

    static func looksLikeHome(for id: ProviderID, root: URL) -> Bool {
        let manager = FileManager.default
        if manager.fileExists(atPath: root.appendingPathComponent(expectedSubpath(for: id)).path) {
            return true
        }
        // Claude keeps sessions/ beside projects/; either marks the home.
        if id == .claudeCode {
            return manager.fileExists(atPath: root.appendingPathComponent("sessions").path)
        }
        return false
    }
}
