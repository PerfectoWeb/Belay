import BelayCore
import BelayHookBridge
import Foundation

/// Tier B across every watched folder: hooks live inside an agent's root, so
/// an agent watched in three folders needs its hooks in all three. One
/// installer per root, derived the way the defaults are. Beside
/// `PreciseDetection` for the file-length rule.
extension PreciseDetection {
    /// The default installer first, then one per extra root, so "the first
    /// one's outcome" keeps meaning what it always did.
    var claudeInstallers: [HookInstaller] {
        [installer]
            + roots(.claudeCode).map {
                HookInstaller(paths: derived(claudeSettings: $0.appendingPathComponent("settings.json")))
            }
    }

    var clineInstallers: [ClineHookInstaller] {
        [clineInstaller] + roots(.cline).map { ClineHookInstaller(paths: derived(clineHome: $0)) }
    }

    var codexInstallers: [CodexHookInstaller] {
        [codexInstaller] + roots(.codex).map { CodexHookInstaller(paths: derived(codexHome: $0)) }
    }

    /// How many extra folders the agent's consent sheet should mention.
    func extraRootsCount(for id: ProviderID) -> Int { roots(id).count }

    /// A folder was added while Precise Detection is already on for the agent:
    /// the consent given in the sheet covers every watched folder (the sheet
    /// says so), so the new root gets its hooks without a second ask.
    func installIfEnabled(for id: ProviderID, at root: URL) async {
        guard let endpoint else { return }
        switch id {
        case .claudeCode where isInstalled:
            let paths = derived(claudeSettings: root.appendingPathComponent("settings.json"))
            do {
                _ = try HookInstaller(paths: paths).install(endpoint: endpoint)
            } catch {
                lastError = error.localizedDescription
            }
        case .cline where isClineInstalled:
            do {
                _ = try ClineHookInstaller(paths: derived(clineHome: root)).install(endpoint: endpoint)
            } catch {
                clineLastError = error.localizedDescription
            }
        case .codex where isCodexInstalled:
            let installer = CodexHookInstaller(paths: derived(codexHome: root))
            let outcome = await Task.detached {
                Result { try installer.install(endpoint: endpoint) }
            }.value
            if case .failure(let error) = outcome {
                codexLastError = error.localizedDescription
            }
        default:
            break
        }
    }

    /// The folder left the watched set: its Belay-marked hooks go with it, or
    /// an unwatched profile keeps posting into the receiver forever.
    func uninstallHooks(for id: ProviderID, at root: URL) async {
        switch id {
        case .claudeCode:
            let paths = derived(claudeSettings: root.appendingPathComponent("settings.json"))
            _ = try? HookInstaller(paths: paths).uninstall()
        case .cline:
            _ = ClineHookInstaller(paths: derived(clineHome: root)).uninstall()
        case .codex:
            let installer = CodexHookInstaller(paths: derived(codexHome: root))
            _ = await Task.detached { try? installer.uninstall() }.value
        default:
            break
        }
    }

    private func derived(claudeSettings: URL) -> BridgePaths {
        BridgePaths(
            support: paths.support, claudeSettings: claudeSettings,
            codexHome: paths.codexHome, clineHome: paths.clineHome)
    }

    private func derived(codexHome: URL) -> BridgePaths {
        BridgePaths(
            support: paths.support, claudeSettings: paths.claudeSettings,
            codexHome: codexHome, clineHome: paths.clineHome)
    }

    private func derived(clineHome: URL) -> BridgePaths {
        BridgePaths(
            support: paths.support, claudeSettings: paths.claudeSettings,
            codexHome: paths.codexHome, clineHome: clineHome)
    }
}
