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
    private let claudeCode: ClaudeCodeProvider
    private let generic: GenericProvider
    private let targetStore = GenericTargetStore()
    let precise: PreciseDetection

    /// `access` and `home` come from the app layer because only it knows which
    /// channel this is (`ClaudeAccess`, `PROJECT_STATE.md` D15). Both default to
    /// the unsandboxed answer so a preview or a test constructs one for free.
    init(
        precise: PreciseDetection,
        access: FileAccessProvider = DirectFileAccess(),
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.precise = precise
        claudeCode = ClaudeCodeProvider(configuration: .claudeHome(home), access: access)
        generic = GenericProvider(access: access)
    }

    /// Starts every provider and returns the merged signal stream.
    ///
    /// A provider that fails to start is logged and skipped rather than fatal:
    /// Tier B failing must never take Tier A down with it, and the app is still
    /// useful in manual modes even with no detection at all.
    func start() async -> AsyncStream<ActivitySignal> {
        let signals = await bus.subscribe()

        await bus.attach(claudeCode.signals)
        await startClaudeCode(first: true)

        await bus.attach(generic.signals)
        await generic.configure(targetStore.load())
        do {
            try await generic.start()
        } catch {
            Log.providers.error("generic provider failed to start: \(error, privacy: .public)")
        }

        if let exact = await precise.start() {
            await bus.attach(exact)
        }
        return signals
    }

    /// Second chance for a provider that refused to start for want of folder
    /// access. The bus is already attached to its stream, so this is a start and
    /// not a re-wire; a provider that is already running ignores it.
    func retryStart() async {
        await startClaudeCode(first: false)
    }

    /// Whether the Claude Code provider is still waiting for something.
    var claudeCodeIsWaiting: Bool {
        get async { await claudeCode.availability.isReady == false }
    }

    /// A folder that does not exist yet is not a failure. It was logged as one
    /// every few seconds on a Mac where Claude Code had never opened a project,
    /// which is the state every new user starts in.
    private func startClaudeCode(first: Bool) async {
        do {
            try await claudeCode.start()
            if !first { Log.providers.notice("Claude Code provider started") }
        } catch ProviderError.notInUseYet(let path) {
            guard first else { return }
            Log.providers.notice("nothing to watch yet at \(path, privacy: .public)")
        } catch {
            guard first else { return }
            Log.providers.error("Claude Code provider failed to start: \(error, privacy: .public)")
        }
    }

    func stop() async {
        await precise.stop()
        await generic.stop()
        await claudeCode.stop()
        await bus.shutdown()
    }

    func statuses(lastSignal: Date?) async -> [ProviderStatus] {
        [
            ProviderStatus(
                descriptor: claudeCode.descriptor,
                availability: await claudeCode.availability,
                isEnabled: true,
                lastSignal: lastSignal
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
