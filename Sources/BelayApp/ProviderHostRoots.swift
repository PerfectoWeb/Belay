import BelayCore
import BelayProviders
import BelaySupport
import Foundation

/// The extra watched folders a built-in agent can have beyond its default home
/// (issue #4: `CLAUDE_CONFIG_DIR` profiles and their siblings). One provider
/// instance per (agent, folder) — the providers are already parametrised by
/// root, so nothing below the app layer changes. Beside `ProviderHost` for the
/// file-length rule.
extension ProviderHost {
    enum RootVerdict: Equatable {
        case added
        /// Already watched, or nested inside (or containing) a watched folder,
        /// which would put two FSEvents streams on one tree.
        case overlaps
    }

    /// The default home the agent is always watched in, for overlap checks and
    /// the tile's menu.
    func defaultRoot(for id: ProviderID) -> URL {
        let name: String
        switch id {
        case .codex: name = ".codex"
        case .cline: name = ".cline"
        case .copilot: name = ".copilot"
        default: name = ".claude"
        }
        return home.appendingPathComponent(name, isDirectory: true)
    }

    /// Builds and starts the instances for every stored extra root. Called once
    /// from `start()`, after the defaults are up.
    func adoptStoredRoots() async {
        for id in [ProviderID.claudeCode, .codex, .cline, .copilot] {
            for root in rootsStore.roots(for: id) {
                await adopt(root: root, for: id)
            }
        }
    }

    /// Validates, persists and starts one more folder for an agent.
    func addRoot(_ url: URL, for id: ProviderID) async -> RootVerdict {
        let root = url.standardizedFileURL.resolvingSymlinksInPath()
        var watched = [defaultRoot(for: id).resolvingSymlinksInPath().path]
        watched += (extras[id] ?? []).map { $0.root.resolvingSymlinksInPath().path }
        for existing in watched {
            let overlapping =
                root.path == existing || root.path.hasPrefix(existing + "/")
                || existing.hasPrefix(root.path + "/")
            if overlapping { return .overlaps }
        }
        rootsStore.add(root, for: id)
        await adopt(root: root, for: id)
        return .added
    }

    func removeRoot(path: String, for id: ProviderID) async {
        rootsStore.remove(path: path, for: id)
        guard let index = extras[id]?.firstIndex(where: { $0.root.path == path }) else { return }
        let entry = extras[id]?.remove(at: index)
        await entry?.instance.stop()
        WatchedFolderAccess.forget(URL(fileURLWithPath: path, isDirectory: true))
    }

    private func adopt(root: URL, for id: ProviderID) async {
        let instance = makeInstance(for: id, root: root)
        extras[id, default: []].append((root: root, instance: instance))
        await attachToBus(instance.signals)
        if enabled.contains(id) { await startExtra(instance, root: root) }
    }

    /// Extras read through the picked-folder grants, the same access the
    /// generic provider uses: in the MAS build the open panel that chose the
    /// folder is the grant.
    private func makeInstance(for id: ProviderID, root: URL) -> any ActivityProvider {
        switch id {
        case .codex: return CodexProvider(configuration: .at(root), access: folders)
        case .cline: return ClineProvider(configuration: .at(root), access: folders)
        case .copilot: return CopilotProvider(configuration: .at(root), access: folders)
        default: return ClaudeCodeProvider(configuration: .at(root), access: folders)
        }
    }

    func setExtrasEnabled(_ on: Bool, for id: ProviderID) async {
        for entry in extras[id] ?? [] {
            if on {
                await startExtra(entry.instance, root: entry.root)
            } else {
                await entry.instance.stop()
            }
        }
    }

    func retryExtras() async {
        for (id, instances) in extras where enabled.contains(id) {
            _ = id
            for entry in instances { await startExtra(entry.instance, root: entry.root) }
        }
    }

    private func startExtra(_ instance: any ActivityProvider, root: URL) async {
        do {
            try await instance.start()
        } catch ProviderError.notInUseYet {
            // The agent has not written there yet; the folder stays watched.
        } catch {
            EventLog.note("extra root start failed \(root.lastPathComponent): \(error)")
        }
    }

    /// One agent's row for the pane: availability is the best across its
    /// folders (ready anywhere is ready), the extras ride along for the menu.
    func status(
        of provider: some ActivityProvider, lastSignals: [ProviderID: Date]
    ) async -> ProviderStatus {
        let id = provider.descriptor.id
        var availability = await provider.availability
        if !availability.isReady {
            for entry in extras[id] ?? [] where await entry.instance.availability.isReady {
                availability = .ready
                break
            }
        }
        return ProviderStatus(
            descriptor: provider.descriptor,
            availability: availability,
            isEnabled: enabled.contains(id),
            lastSignal: lastSignals[id],
            customRoots: (extras[id] ?? []).map { $0.root.path }
        )
    }

}
