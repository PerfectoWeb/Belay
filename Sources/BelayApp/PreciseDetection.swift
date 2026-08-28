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

    private let receiver: HookReceiver
    let installer: HookInstaller
    // Internal, with their flags: the Codex and Cline halves live in
    // `PreciseDetectionAgents.swift` for the file-length rule.
    let codexInstaller: CodexHookInstaller
    let clineInstaller: ClineHookInstaller
    let paths: BridgePaths
    /// The extra watched folders per agent, injected so a stand or test with
    /// scratch paths never reaches the user's real roots. Hooks live inside
    /// each root, so "Precise" for an agent means every folder it is watched in.
    let roots: (ProviderID) -> [URL]

    /// Injectable so a stand or a test can point the whole tier at a scratch
    /// tree; the app takes the default and never notices.
    init(paths: BridgePaths = .real(), roots: @escaping (ProviderID) -> [URL] = { _ in [] }) {
        receiver = HookReceiver(store: BridgeEndpointStore(paths: paths))
        installer = HookInstaller(paths: paths)
        codexInstaller = CodexHookInstaller(paths: paths)
        clineInstaller = ClineHookInstaller(paths: paths)
        self.paths = paths
        self.roots = roots
    }
    private(set) var endpoint: BridgeEndpoint?
    private(set) var isInstalled = false
    var isCodexInstalled = false
    var isClineInstalled = false
    var lastError: String?
    var codexLastError: String?
    var clineLastError: String?

    var settingsPath: String { installer.settingsURL.path }
    var codexHooksPath: String { codexInstaller.hooksURL.path }
    var clineHooksPath: String { clineInstaller.hooksURL.path }

    /// Starts the receiver. Deliberately does **not** install hooks: the
    /// listener is harmless on its own, and the user has not agreed to anything.
    ///
    /// Nothing binds in the App Store build. Without the entitlement the bind
    /// would fail anyway; refusing here means one clear reason in the log
    /// instead of a network error that reads like a fault.
    func start() async -> AsyncStream<ActivitySignal>? {
        guard Self.isSupported else {
            Log.bridge.notice("no hook bridge in this build; detection is the transcript watcher")
            EventLog.note("bridge absent in this build")
            return nil
        }
        do {
            endpoint = try await receiver.start()
            isInstalled = (try? installer.isInstalled()) ?? false
            isCodexInstalled = (try? codexInstaller.isInstalled()) ?? false
            isClineInstalled = clineInstaller.isInstalled()
            await selfHeal()
            return await receiver.signals
        } catch {
            Log.bridge.error("hook receiver failed to start: \(error.localizedDescription, privacy: .public)")
            EventLog.note("bridge did not start: \(error.localizedDescription)")
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
        guard let endpoint else { return }
        if isInstalled { healClaude(endpoint) }
        if isClineInstalled { healCline(endpoint) }
        if isCodexInstalled { await healCodex(endpoint) }
    }

    private func healClaude(_ endpoint: BridgeEndpoint) {
        for installer in claudeInstallers {
            do {
                if case .written = try installer.reconcile(endpoint: endpoint) {
                    Log.bridge.notice("repointed existing hooks at the current port")
                    EventLog.note("bridge repointed claude hooks port=\(endpoint.port)")
                }
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private func healCline(_ endpoint: BridgeEndpoint) {
        for installer in clineInstallers {
            do {
                if case .written = try installer.reconcile(endpoint: endpoint) {
                    Log.bridge.notice("repointed existing Cline hooks at the current port")
                    EventLog.note("bridge repointed cline hooks port=\(endpoint.port)")
                }
            } catch {
                clineLastError = error.localizedDescription
            }
        }
    }

    /// Off the main thread because a codex rewrite must re-trust, and that
    /// spawns `codex app-server`. Only runs when installed and drifted.
    private func healCodex(_ endpoint: BridgeEndpoint) async {
        let installers = codexInstallers
        let outcome = await Task.detached {
            Result {
                for installer in installers {
                    if case .written = try installer.reconcile(endpoint: endpoint) {
                        Log.bridge.notice("repointed existing Codex hooks at the current port")
                        EventLog.note("bridge repointed codex hooks port=\(endpoint.port)")
                    }
                }
            }
        }.value
        if case .failure(let error) = outcome {
            codexLastError = error.localizedDescription
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
        lastError = nil
        // Every watched folder, not only ~/.claude: hooks live inside the
        // root, and the sheet's consent names them all.
        for installer in claudeInstallers {
            do {
                _ = try installer.install(endpoint: endpoint)
            } catch {
                lastError = error.localizedDescription
            }
        }
        isInstalled = (try? installer.isInstalled()) ?? false
        return lastError == nil
    }

    @discardableResult
    func uninstall() -> Bool {
        lastError = nil
        for installer in claudeInstallers {
            do {
                _ = try installer.uninstall()
            } catch {
                lastError = error.localizedDescription
            }
        }
        isInstalled = false
        return lastError == nil
    }
}
