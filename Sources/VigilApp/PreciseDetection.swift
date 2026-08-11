import Foundation
import VigilCore
import VigilHookBridge
import VigilSupport

/// Owns the Tier B lifecycle for the app layer: run the receiver, and mediate
/// every change to the user's `settings.json`.
///
/// `docs/00-INVARIANTS.md` invariant 6 is the whole design here — Vigil never writes to
/// `~/.claude/` without explicit, per-action consent in the UI, and always makes
/// a timestamped backup first. Nothing in this type writes as a side effect of
/// starting up; `install` and `uninstall` are only ever called from a button.
@MainActor
final class PreciseDetection {
    private let receiver = HookReceiver()
    private let installer = HookInstaller()
    private(set) var endpoint: BridgeEndpoint?
    private(set) var isInstalled = false
    private(set) var lastError: String?

    var settingsPath: String { installer.settingsURL.path }

    /// Starts the receiver. Deliberately does **not** install hooks: the
    /// listener is harmless on its own, and the user has not agreed to anything.
    func start() async -> AsyncStream<ActivitySignal>? {
        do {
            endpoint = try await receiver.start()
            isInstalled = (try? installer.isInstalled()) ?? false
            await selfHeal()
            return await receiver.signals
        } catch {
            Log.bridge.error("hook receiver failed to start: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
            return nil
        }
    }

    func stop() async {
        await receiver.stop()
        endpoint = nil
    }

    /// Rewrites Vigil's own entries when the port has changed since last launch.
    ///
    /// This is a write to `settings.json` with no button behind it, so it is
    /// deliberately narrow: it runs only when the user has *already* consented
    /// to an installation, and it can only update entries Vigil owns. It never
    /// adds an integration that was not there, which is what invariant 6 exists
    /// to prevent. Without it, moving the app or a new port silently breaks
    /// detection with no visible cause (docs/03).
    private func selfHeal() async {
        guard isInstalled, let endpoint else { return }
        do {
            if case .written = try installer.reconcile(endpoint: endpoint) {
                Log.bridge.notice("repointed existing hooks at the current port")
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func preview() -> HookInstaller.Preview? {
        guard let endpoint else { return nil }
        return try? installer.preview(endpoint: endpoint)
    }

    /// The block to show when the file cannot be edited safely, so the user can
    /// paste it themselves rather than being told "no" with no way forward.
    func manualSnippet() -> String? {
        guard let endpoint else { return nil }
        return try? HookInstaller.snippet(for: endpoint)
    }

    @discardableResult
    func install() -> Bool {
        guard let endpoint else { return false }
        do {
            _ = try installer.install(endpoint: endpoint)
            isInstalled = true
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func uninstall() -> Bool {
        do {
            _ = try installer.uninstall()
            isInstalled = false
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}
