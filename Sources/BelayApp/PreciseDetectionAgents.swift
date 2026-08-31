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

extension PreciseDetection {
    // MARK: - Parking across quits

    /// The quit half of parking: Belay's own entries leave the agents'
    /// settings, so an agent used between quit and relaunch posts to nothing
    /// and errors at nothing, instead of filling its terminal with
    /// `ECONNREFUSED` against a port nobody answers. Only entries Belay owns,
    /// under the standing consent that installed them; what was removed is
    /// recorded, and only that comes back. Codex is deliberately not parked —
    /// its uninstall re-trusts the project by spawning `codex app-server`,
    /// which has no place inside a one-second quit.
    func parkForQuit() {
        guard Self.isSupported else { return }
        var parked = ParkedHooks()
        if (try? installer.isInstalled()) == true {
            for installer in claudeInstallers { _ = try? installer.uninstall() }
            parked.claude = true
        }
        if clineInstaller.isInstalled() {
            for installer in clineInstallers { _ = installer.uninstall() }
            parked.cline = true
        }
        guard !parked.isEmpty else { return }
        ParkedHooksStore(paths: paths).save(parked)
        EventLog.note("bridge parked hooks for quit")
    }

    /// The launch half: exactly what a quit removed, back where it was, at the
    /// current port. Consumes the record, so it cannot re-add twice.
    func restoreParked() {
        let store = ParkedHooksStore(paths: paths)
        guard let parked = store.load(), let endpoint else { return }
        if parked.claude {
            for installer in claudeInstallers { _ = try? installer.install(endpoint: endpoint) }
        }
        if parked.cline {
            for installer in clineInstallers { _ = try? installer.install(endpoint: endpoint) }
        }
        store.clear()
        EventLog.note("bridge restored parked hooks port=\(endpoint.port)")
    }
}
