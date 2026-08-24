import BelayCore
import BelayProviders
import BelaySupport
import Foundation

/// Owns the providers and the bus that fans them together.
///
/// Split out of `BelayController` once it had grown two jobs: this one is
/// "where do signals come from", the controller's is "what happens to them".
/// Adding a provider means touching this file and nothing else in the app layer.
@MainActor
final class ProviderHost {
    private let bus = SignalBus()
    // Internal, not private: the per-provider start helpers live in
    // `ProviderHostStarts.swift` for the file-length rule.
    let claudeCode: ClaudeCodeProvider
    let codex: CodexProvider
    let cline: ClineProvider
    let copilot: CopilotProvider
    let generic: GenericProvider
    private let targetStore = GenericTargetStore()
    let precise: PreciseDetection
    /// Which built-in agents are switched on. A switched-off agent is not
    /// started, not asked about, and never nags for a folder it would read.
    private(set) var enabled: Set<ProviderID>

    /// `access`, `folders` and `home` come from the app layer because only it
    /// knows which channel this is (`ClaudeAccess`, `WatchedFolderAccess`,
    /// `docs/PROJECT_STATE.md` D15). All three default to the unsandboxed answer so a
    /// preview or a test constructs one for free.
    ///
    /// Two access objects, not one. `access` is the grant for `~/.claude`;
    /// `folders` is the grant for whatever the user picked for a generic target.
    /// They were the same object once, and that quietly meant a sandboxed build
    /// could never read a picked folder, because no folder a user picks is
    /// inside `~/.claude`.
    init(
        precise: PreciseDetection,
        enabled: Set<ProviderID> = [.claudeCode, .codex],
        access: FileAccessProvider = DirectFileAccess(),
        codexAccess: FileAccessProvider = DirectFileAccess(),
        clineAccess: FileAccessProvider = DirectFileAccess(),
        copilotAccess: FileAccessProvider = DirectFileAccess(),
        folders: FileAccessProvider = DirectFileAccess(),
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.precise = precise
        self.enabled = enabled
        claudeCode = ClaudeCodeProvider(configuration: .claudeHome(home), access: access)
        codex = CodexProvider(configuration: .codexHome(home), access: codexAccess)
        cline = ClineProvider(configuration: .clineHome(home), access: clineAccess)
        copilot = CopilotProvider(configuration: .copilotHome(home), access: copilotAccess)
        generic = GenericProvider(access: folders)
    }

    /// Starts every provider and returns the merged signal stream.
    ///
    /// A provider that fails to start is logged and skipped rather than fatal:
    /// Tier B failing must never take Tier A down with it, and the app is still
    /// useful in manual modes even with no detection at all.
    func start() async -> AsyncStream<ActivitySignal> {
        let signals = await bus.subscribe()
        EventLog.note("providers start enabled=\(enabled.map(\.rawValue).sorted().joined(separator: ","))")

        await bus.attach(claudeCode.signals)
        if enabled.contains(.claudeCode) { await startClaudeCode(first: true) }

        await bus.attach(codex.signals)
        if enabled.contains(.codex) { await startCodex(first: true) }

        await bus.attach(cline.signals)
        if enabled.contains(.cline) { await startCline(first: true) }

        await bus.attach(copilot.signals)
        if enabled.contains(.copilot) { await startCopilot(first: true) }

        await bus.attach(generic.signals)
        await generic.configure(targetStore.load())
        do {
            try await generic.start()
        } catch {
            Log.providers.error("generic provider failed to start: \(error, privacy: .public)")
        }

        if let exact = await precise.start() {
            await bus.attach(gatedByEnabled(exact))
        }
        return signals
    }

    /// Hook posts arrive whether or not the agent's switch is on — the
    /// CLI-side install knows nothing about Belay's toggles — so the exact
    /// stream is where the switch is enforced on the way in. Generic webhook
    /// signals ride the same stream and pass untouched: their enablement is
    /// the target list, not this set.
    private func gatedByEnabled(_ stream: AsyncStream<ActivitySignal>) -> AsyncStream<ActivitySignal> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                for await signal in stream {
                    guard let self else { break }
                    let gated = signal.provider != .generic
                    if gated, !enabled.contains(signal.provider) { continue }
                    continuation.yield(signal)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Second chance for a provider that refused to start for want of folder
    /// access. The bus is already attached to its stream, so this is a start and
    /// not a re-wire; a provider that is already running ignores it.
    func retryStart() async {
        if enabled.contains(.claudeCode) { await startClaudeCode(first: false) }
        if enabled.contains(.codex) { await startCodex(first: false) }
        if enabled.contains(.cline) { await startCline(first: false) }
        if enabled.contains(.copilot) { await startCopilot(first: false) }
    }

    /// Switches a built-in agent on or off at runtime: the provider starts or
    /// stops, and the streams stay attached so turning it back on is a start
    /// and not a re-wire.
    func setEnabled(_ set: Set<ProviderID>) async {
        let was = enabled
        enabled = set
        if set.contains(.claudeCode) != was.contains(.claudeCode) {
            if set.contains(.claudeCode) {
                await startClaudeCode(first: false)
            } else {
                await claudeCode.stop()
            }
        }
        if set.contains(.codex) != was.contains(.codex) {
            if set.contains(.codex) { await startCodex(first: false) } else { await codex.stop() }
        }
        if set.contains(.cline) != was.contains(.cline) {
            if set.contains(.cline) { await startCline(first: false) } else { await cline.stop() }
        }
        if set.contains(.copilot) != was.contains(.copilot) {
            if set.contains(.copilot) {
                await startCopilot(first: false)
            } else {
                await copilot.stop()
            }
        }
    }

    /// Whether the Claude Code provider is still waiting for something.
    var claudeCodeIsWaiting: Bool {
        get async { await claudeCode.availability.isReady == false }
    }

    func stop() async {
        await precise.stop()
        await generic.stop()
        await copilot.stop()
        await cline.stop()
        await codex.stop()
        await claudeCode.stop()
        await bus.shutdown()
    }

    func statuses(lastSignals: [ProviderID: Date] = [:]) async -> [ProviderStatus] {
        [
            ProviderStatus(
                descriptor: claudeCode.descriptor,
                availability: await claudeCode.availability,
                isEnabled: enabled.contains(.claudeCode),
                lastSignal: lastSignals[.claudeCode]
            ),
            ProviderStatus(
                descriptor: codex.descriptor,
                availability: await codex.availability,
                isEnabled: enabled.contains(.codex),
                lastSignal: lastSignals[.codex]
            ),
            ProviderStatus(
                descriptor: cline.descriptor,
                availability: await cline.availability,
                isEnabled: enabled.contains(.cline),
                lastSignal: lastSignals[.cline]
            ),
            ProviderStatus(
                descriptor: copilot.descriptor,
                availability: await copilot.availability,
                isEnabled: enabled.contains(.copilot),
                lastSignal: lastSignals[.copilot]
            ),
            ProviderStatus(
                descriptor: generic.descriptor,
                availability: await generic.availability,
                isEnabled: !targets.isEmpty,
                lastSignal: nil
            )
        ]
    }

    var targets: [GenericTarget] { targetStore.load() }

    /// Applies a configuration change immediately as well as persisting it, so a
    /// user who adds a preset does not have to restart to see it work.
    func updateTargets(_ targets: [GenericTarget]) async {
        targetStore.save(targets)
        await generic.configure(targets)
    }
}
