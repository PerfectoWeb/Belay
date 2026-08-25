import AppKit
import BelayCore
import BelayProviders
import BelaySettings
import Foundation

/// The built-in agents' switches: what starts on, and what a toggle does.
/// Beside `BelayController` for the file-length rule.
extension BelayController {
    /// The pane's provider callbacks, wired here so `start()` stays one line.
    func wireProviderCallbacks() {
        state.onToggleProvider = { [weak self] provider, on in
            self?.setProviderEnabled(provider, on)
        }
        state.onAddProviderRoot = { [weak self] provider in self?.addProviderRoot(provider) }
        state.onRemoveProviderRoot = { [weak self] provider, path in
            self?.removeProviderRoot(provider, path: path)
        }
        state.onAddSuggestedRoot = { [weak self] provider, path in
            self?.addSuggestedRoot(provider, path: path)
        }
    }

    /// A suggested sibling profile, adopted with one click: it was found by
    /// scanning, so it already looks like the agent's home and needs no panel
    /// (direct build only; the sandbox never suggests).
    func addSuggestedRoot(_ id: ProviderID, path: String) {
        Task { [providers, weak self] in
            let root = URL(fileURLWithPath: path, isDirectory: true)
            if await providers.addRoot(root, for: id) == .added {
                await providers.precise.installIfEnabled(for: id, at: root)
            }
            await self?.publishProviderStatus()
        }
    }

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

    /// "Add Folder" in a tile's menu: the open panel doubles as the sandbox
    /// grant, a folder that does not look like the agent's home gets a soft
    /// warning, and an overlap with something already watched is refused.
    func addProviderRoot(_ id: ProviderID) {
        let name = state.providers.first { $0.id == id }?.descriptor.displayName ?? ""
        let picked = ClaudeFolderPanel.run(
            startingAt: FileManager.default.homeDirectoryForCurrentUser,
            message: String(localized: "Choose another folder \(name) keeps its sessions in."),
            prompt: String(localized: "Watch Folder"))
        guard let picked else { return }
        let plausible = BuiltInRoots.looksLikeHome(for: id, root: picked)
        let expected = BuiltInRoots.expectedSubpath(for: id)
        if !plausible, !confirmUnlikelyRoot(agent: name, expected: expected) { return }
        WatchedFolderAccess.remember(picked)
        Task { [providers, weak self] in
            if await providers.addRoot(picked, for: id) == .overlaps {
                WatchedFolderAccess.forget(picked)
                self?.showOverlapNote(agent: name)
            } else {
                // Precise Detection already on for this agent covers every
                // watched folder; the new one gets its hooks too.
                await providers.precise.installIfEnabled(for: id, at: picked)
            }
            await self?.publishProviderStatus()
        }
    }

    func removeProviderRoot(_ id: ProviderID, path: String) {
        let name = state.providers.first { $0.id == id }?.descriptor.displayName ?? ""
        let shown = (path as NSString).abbreviatingWithTildeInPath
        let alert = NSAlert()
        alert.messageText = String(localized: "Stop watching \"\(shown)\"?")
        alert.informativeText = String(
            localized: """
                Belay will stop watching this folder for \(name). Any Belay hooks \
                inside it are removed as well. The folder itself is not touched.
                """)
        alert.addButton(withTitle: String(localized: "Remove Folder"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        // The folder-with-minus in the same red as the destructive title, so
        // the button says what it does before the words are read.
        alert.buttons.first?.image = NSImage(
            systemSymbolName: "folder.badge.minus", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [.systemRed]))
        alert.buttons.first?.imagePosition = .imageLeading
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { [providers, weak self] in
            let root = URL(fileURLWithPath: path, isDirectory: true)
            await providers.precise.uninstallHooks(for: id, at: root)
            await providers.removeRoot(path: path, for: id)
            await self?.publishProviderStatus()
        }
    }

    private func confirmUnlikelyRoot(agent: String, expected: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "This folder does not look like a \(agent) folder.")
        alert.informativeText = String(
            localized: """
                Belay expected to find "\(expected)" inside. You can watch it anyway, and it \
                will simply stay quiet until \(agent) writes there.
                """)
        alert.addButton(withTitle: String(localized: "Watch Anyway"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showOverlapNote(agent: String) {
        let alert = NSAlert()
        alert.messageText = String(
            localized: "Belay already watches this folder for \(agent), or one that contains it.")
        alert.runModal()
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
