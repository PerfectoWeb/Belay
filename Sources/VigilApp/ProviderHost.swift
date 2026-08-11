import Foundation
import VigilCore
import VigilProviders
import VigilSupport

/// Owns the providers and the bus that fans them together.
///
/// Split out of `VigilController` once it had grown two jobs: this one is
/// "where do signals come from", the controller's is "what happens to them".
/// Adding a provider means touching this file and nothing else in the app layer.
@MainActor
final class ProviderHost {
    private let bus = SignalBus()
    private let claudeCode = ClaudeCodeProvider()
    private let generic = GenericProvider()
    private let targetStore = GenericTargetStore()
    let precise: PreciseDetection

    init(precise: PreciseDetection) {
        self.precise = precise
    }

    /// Starts every provider and returns the merged signal stream.
    ///
    /// A provider that fails to start is logged and skipped rather than fatal:
    /// Tier B failing must never take Tier A down with it, and the app is still
    /// useful in manual modes even with no detection at all.
    func start() async -> AsyncStream<ActivitySignal> {
        let signals = await bus.subscribe()

        await bus.attach(claudeCode.signals)
        do {
            try await claudeCode.start()
        } catch {
            Log.providers.error("Claude Code provider failed to start: \(error, privacy: .public)")
        }

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
