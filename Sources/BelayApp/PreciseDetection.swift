import BelayCore
import BelayHookBridge
import BelaySupport
import Foundation

/// Owns the Tier B lifecycle for the app layer: run the receiver, and mediate
/// every change to the user's `settings.json`.
///
/// `docs/00-INVARIANTS.md` invariant 6 is the whole design here — Belay never writes to
/// `~/.claude/` without explicit, per-action consent in the UI, and always makes
/// a timestamped backup first. Nothing in this type writes as a side effect of
/// starting up; `install` and `uninstall` are only ever called from a button.
@MainActor
final class PreciseDetection {
    /// Whether this build has a hook bridge at all.
    ///
    /// False in the App Store build, for two reasons that arrive at the same
    /// answer.
    ///
    /// It cannot work there. `HookInstaller` edits `~/.claude/settings.json`,
    /// and inside the sandbox `FileManager.homeDirectoryForCurrentUser` answers
    /// with the container, so "Enable" would write a hook file into a directory
    /// Claude Code has never heard of and report success. The transcript
    /// watcher reaches the real folder because a bookmark points it there;
    /// nothing pointed the installer anywhere.
    ///
    /// And it costs an entitlement. A loopback listener needs
    /// `com.apple.security.network.server`, which App Review asked about twice,
    /// correctly: guideline 2.4.5 is that an app carries the minimum
    /// entitlements it needs, and an entitlement whose only feature does not
    /// function is not minimum. It is out of `Belay-MAS.entitlements` now, and
    /// `verify-mas-build.sh` fails the build if it comes back.
    ///
    /// Nothing is lost that worked. Detection in that build is the transcript
    /// watcher, which is the default everywhere and needs no network at all.
    static var isSupported: Bool {
        #if BELAY_MAS
        false
        #else
        true
        #endif
    }

    private let receiver = HookReceiver()
    private let installer = HookInstaller()
    private(set) var endpoint: BridgeEndpoint?
    private(set) var isInstalled = false
    private(set) var lastError: String?

    var settingsPath: String { installer.settingsURL.path }

    /// Starts the receiver. Deliberately does **not** install hooks: the
    /// listener is harmless on its own, and the user has not agreed to anything.
    ///
    /// Nothing binds in the App Store build. Without the entitlement the bind
    /// would fail anyway; refusing here means one clear reason in the log
    /// instead of a network error that reads like a fault.
    func start() async -> AsyncStream<ActivitySignal>? {
        guard Self.isSupported else {
            Log.bridge.notice("no hook bridge in this build; detection is the transcript watcher")
            return nil
        }
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

    /// Rewrites Belay's own entries when the port has changed since last launch.
    ///
    /// This is a write to `settings.json` with no button behind it, so it is
    /// deliberately narrow: it runs only when the user has *already* consented
    /// to an installation, and it can only update entries Belay owns. It never
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
