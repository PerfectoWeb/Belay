import BelayProviders
import BelaySupport

/// The per-provider start helpers. Beside `ProviderHost` for the file-length
/// rule.
///
/// Each logs a "started" line only on a genuine not-watching → watching
/// transition. `start()` is a silent no-op when already running, and the
/// arrival watcher retries every 30 s for the app's whole life on a Mac where
/// an agent is never installed — so an unconditional log there wrote a false
/// "started" line every half minute.
extension ProviderHost {
    /// A folder that does not exist yet is not a failure. It was logged as one
    /// every few seconds on a Mac where Claude Code had never opened a project,
    /// which is the state every new user starts in.
    func startClaudeCode(first: Bool) async {
        let wasWatching = await claudeCode.isWatching
        do {
            try await claudeCode.start()
            if !wasWatching, await claudeCode.isWatching {
                Log.providers.notice("Claude Code provider started")
            }
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
        let wasWatching = await codex.isWatching
        do {
            try await codex.start()
            if !wasWatching, await codex.isWatching {
                Log.providers.notice("Codex provider started")
            }
        } catch ProviderError.notInUseYet(let path) {
            guard first else { return }
            Log.providers.notice("nothing to watch yet at \(path, privacy: .public)")
        } catch {
            guard first else { return }
            Log.providers.error("Codex provider failed to start: \(error, privacy: .public)")
        }
    }

    func startCline(first: Bool) async {
        let wasWatching = await cline.isWatching
        do {
            try await cline.start()
            if !wasWatching, await cline.isWatching { EventLog.note("cline provider started") }
        } catch ProviderError.notInUseYet(let path) {
            if first { EventLog.note("cline not in use yet \(path)") }
        } catch {
            EventLog.note("cline start failed \(error)")
        }
    }

    func startCopilot(first: Bool) async {
        let wasWatching = await copilot.isWatching
        do {
            try await copilot.start()
            if !wasWatching, await copilot.isWatching { EventLog.note("copilot provider started") }
        } catch ProviderError.notInUseYet(let path) {
            if first { EventLog.note("copilot not in use yet \(path)") }
        } catch {
            EventLog.note("copilot start failed \(error)")
        }
    }
}
