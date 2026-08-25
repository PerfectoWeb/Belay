import BelayCore
import BelayHookBridge
import BelaySupport
import Foundation

/// The Codex and Cline halves of Tier B: their installers' lifecycles, beside
/// `PreciseDetection` for the file-length rule.
extension PreciseDetection {
    // MARK: - Cline

    func clinePreview() -> String? {
        guard let endpoint else { return nil }
        return clineInstaller.preview(endpoint: endpoint)
    }

    /// File names Belay would want that are already taken by scripts it does
    /// not own; those events are skipped, and the sheet says so.
    func clineOccupied() -> [String] { clineInstaller.occupied() }

    @discardableResult
    func installCline() -> Bool {
        guard let endpoint else { return false }
        clineLastError = nil
        for installer in clineInstallers {
            do {
                _ = try installer.install(endpoint: endpoint)
            } catch {
                clineLastError = error.localizedDescription
            }
        }
        isClineInstalled = clineInstaller.isInstalled()
        return clineLastError == nil
    }

    @discardableResult
    func uninstallCline() -> Bool {
        for installer in clineInstallers { _ = installer.uninstall() }
        isClineInstalled = false
        clineLastError = nil
        return true
    }

    // MARK: - Codex

    func codexPreview() -> HookInstaller.Preview? {
        guard let endpoint else { return nil }
        return try? codexInstaller.preview(endpoint: endpoint)
    }

    /// Async because trusting the hooks spawns `codex app-server`; the button
    /// that calls this shows its own progress and nothing else blocks on it.
    func installCodex() async -> Bool {
        guard let endpoint else { return false }
        let installers = codexInstallers
        let outcome = await Task.detached {
            Result {
                for installer in installers { _ = try installer.install(endpoint: endpoint) }
            }
        }.value
        switch outcome {
        case .success:
            isCodexInstalled = true
            codexLastError = nil
            return true
        case .failure(let error):
            // The file may have been written before the trust step failed, so
            // read the truth back rather than assuming nothing happened.
            isCodexInstalled = (try? codexInstaller.isInstalled()) ?? false
            codexLastError = error.localizedDescription
            return false
        }
    }

    func uninstallCodex() async -> Bool {
        let installers = codexInstallers
        let outcome = await Task.detached {
            Result {
                for installer in installers { _ = try installer.uninstall() }
            }
        }.value
        switch outcome {
        case .success:
            isCodexInstalled = false
            codexLastError = nil
            return true
        case .failure(let error):
            codexLastError = error.localizedDescription
            return false
        }
    }
}
