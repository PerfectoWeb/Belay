import BelayProviders
import BelaySupport

/// The per-provider start helpers. Beside `ProviderHost` for the file-length
/// rule.
extension ProviderHost {
    /// A folder that does not exist yet is not a failure. It was logged as one
    /// every few seconds on a Mac where Claude Code had never opened a project,
    /// which is the state every new user starts in.
    func startClaudeCode(first: Bool) async {
        do {
            try await claudeCode.start()
            if !first { Log.providers.notice("Claude Code provider started") }
        } catch ProviderError.notInUseYet(let path) {
            guard first else { return }
            Log.providers.notice("nothing to watch yet at \(path, privacy: .public)")
        } catch {
            guard first else { return }
            Log.providers.error("Claude Code provider failed to start: \(error, privacy: .public)")
        }
    }

    /// Same shape as the Claude Code start: a Mac where Codex has never run is
    /// the state every user starts in, not an error worth shouting about.
    func startCodex(first: Bool) async {
        do {
            try await codex.start()
            if !first { Log.providers.notice("Codex provider started") }
        } catch ProviderError.notInUseYet(let path) {
            guard first else { return }
            Log.providers.notice("nothing to watch yet at \(path, privacy: .public)")
        } catch {
            guard first else { return }
            Log.providers.error("Codex provider failed to start: \(error, privacy: .public)")
        }
    }

    func startCline(first: Bool) async {
        do {
            try await cline.start()
            EventLog.note("cline provider started")
        } catch ProviderError.notInUseYet(let path) {
            EventLog.note("cline not in use yet \(path)")
        } catch {
            EventLog.note("cline start failed \(error)")
        }
    }

    func startCopilot(first: Bool) async {
        do {
            try await copilot.start()
            EventLog.note("copilot provider started")
        } catch ProviderError.notInUseYet(let path) {
            EventLog.note("copilot not in use yet \(path)")
        } catch {
            EventLog.note("copilot start failed \(error)")
        }
    }
}
