import BelayCore
import BelayProviders
import BelaySettings
import Foundation

/// The built-in agents' switches: what starts on, and what a toggle does.
/// Beside `BelayController` for the file-length rule.
extension BelayController {
    /// A built-in agent switched on or off from Settings. Switching one on
    /// is also the moment to ask for its folder, if this build has to ask:
    /// the person just said they want it watched.
    func setProviderEnabled(_ provider: ProviderID, _ on: Bool) {
        var set = settings.enabledProviders
        if on { set.insert(provider) } else { set.remove(provider) }
        settings.enabledProviders = set
        Task { [providers, weak self] in
            await providers.setEnabled(set)
            await self?.publishProviderStatus()
            guard on, let status = self?.state.providers.first(where: { $0.id == provider }),
                case .needsSetup = status.availability
            else { return }
            self?.requestProviderAccess(provider)
        }
    }

    static func detectBuiltIns(settings: SettingsStore) {
        guard !settings.builtInsDetected else { return }
        settings.builtInsDetected = true
        #if !BELAY_MAS
        let home = FileManager.default.homeDirectoryForCurrentUser
        var set: Set<ProviderID> = []
        if FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude").path) {
            set.insert(.claudeCode)
        }
        if FileManager.default.fileExists(atPath: home.appendingPathComponent(".codex").path) {
            set.insert(.codex)
        }
        if FileManager.default.fileExists(atPath: home.appendingPathComponent(".cline").path) {
            set.insert(.cline)
        }
        if FileManager.default.fileExists(atPath: home.appendingPathComponent(".copilot").path) {
            set.insert(.copilot)
        }
        settings.enabledProviders = set
        #endif
    }

    func requestProviderAccess(_ provider: ProviderID) {
        let granted: Bool
        switch provider {
        case .codex: granted = CodexAccess.request()
        case .cline: granted = ClineAccess.request()
        case .copilot: granted = CopilotAccess.request()
        default: granted = ClaudeAccess.request()
        }
        Task { [weak self] in
            if granted { await self?.providers.retryStart() }
            await self?.publishProviderStatus()
        }
    }

    func updateGenericTargets(_ targets: [GenericTarget]) {
        Task { [providers] in await providers.updateTargets(targets) }
    }

    /// Banks the in-progress hold to statistics from the termination-signal
    /// path, which calls `exit(0)` before `applicationWillTerminate` can run
    /// the graceful `shutdown()` flush. A no-op when nothing is held, and
    /// idempotent with the graceful flush (`flush` clears the run it banks).
    func bankUsageOnTermination() { usage.flush() }

    /// Closes every sandboxed access scope on the way out — all five, or the
    /// ones left open are the per-process scope leak docs/06 warns about (the
    /// count left behind must be zero). No-ops in the direct build.
    func relinquishAllScopes() {
        ClaudeAccess.relinquish()
        CodexAccess.relinquish()
        ClineAccess.relinquish()
        CopilotAccess.relinquish()
        WatchedFolderAccess.relinquish()
    }

}
