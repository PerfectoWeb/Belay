import BelayCore
import Foundation
import Testing

@testable import BelayProviders

@Suite("Generic presets and webhook reports")
struct GenericPresetTests {
    private let scratch = GenericScratch()

    @Test("Every preset fills in a configuration the provider can actually use")
    func presetsAreValid() async throws {
        #expect(GenericPreset.all.count >= 3)
        #expect(Set(GenericPreset.all.map(\.id)).count == GenericPreset.all.count)

        for preset in GenericPreset.all {
            let picked = preset.folderPrompt == nil ? nil : scratch.root
            let target = preset.target(home: scratch.root, folder: picked)
            #expect(!target.displayName.isEmpty)
            #expect(!preset.summary.isEmpty)
            #expect(target.watchedFolder != nil)
            #expect(target.isConfigured)
            // docs/DISCOVERY §2.2: the default quiet period is not negotiable.
            #expect(target.inferredIdleAfter == 45)
        }
    }

    @Test("A preset that cannot know the path asks for one instead of guessing")
    func userPickedPresetsPrompt() {
        let aider = GenericPreset.all.first { $0.id == "aider" }
        #expect(aider?.folderPrompt != nil)
        // With no folder picked yet the target is still configured, because the
        // process name and webhook identifier stand on their own.
        let unpicked = aider?.target(home: scratch.root, folder: nil)
        #expect(unpicked?.watchedFolder == nil)
        #expect(unpicked?.isConfigured == true)
    }

    /// D4's successor: the day the rollout format was verified on a real
    /// install, Codex graduated to `CodexProvider`. A preset row beside the
    /// first-class provider would report every session twice, so the list must
    /// not grow one back.
    @Test("Codex is a first-class provider, not a preset")
    func codexIsNotAPreset() {
        #expect(GenericPreset.all.allSatisfy { $0.id != "codex" })
        #expect(GenericPreset.matching(name: "Codex CLI") == nil)
    }

    @Test("A quiet period below the measured floor is clamped, not honoured")
    func quietPeriodIsClamped() {
        let hasty = GenericTarget(displayName: "Hasty", inferredIdleAfter: 1)
        #expect(hasty.inferredIdleAfter == GenericTarget.quietPeriodRange.lowerBound)
        #expect(hasty.isConfigured == false)
    }

    @Test("The webhook state vocabulary maps to activities, and drops the unknown")
    func webhookStates() {
        #expect(GenericWebhookReport(identifier: "aider", state: "working")?.activity == .working)
        #expect(GenericWebhookReport(identifier: "aider", state: "STOP")?.activity == .idle)
        #expect(GenericWebhookReport(identifier: "aider", state: "waiting")?.activity == .awaitingUser)
        #expect(GenericWebhookReport(identifier: "aider", state: "ended")?.activity == .ended)
        #expect(GenericWebhookReport(identifier: "aider", state: "probably") == nil)
        #expect(GenericWebhookReport(identifier: "", state: "working") == nil)
    }

    @Test("A routed report is attributed to its target, or becomes its own session")
    func webhookAttribution() async throws {
        let clock = SteppedClock()
        let configured = GenericTarget(displayName: "Aider", webhookIdentifier: "aider")
        let provider = GenericProvider(targets: [configured], clock: clock)
        let collector = SignalCollector()
        await collector.attach(to: await provider.signals)

        await provider.ingest(GenericWebhookReport(identifier: "aider", activity: .working))
        await provider.ingest(
            GenericWebhookReport(identifier: "unknown-tool", activity: .working, workspace: "demo"))
        let opened = await collector.wait(for: 2)
        #expect(opened.first?.session == configured.session)
        #expect(opened.first?.workspace == "Aider")
        #expect(opened.last?.session == SessionID("generic:unknown-tool"))
        // Nothing about a local caller is verified, so nothing it says is exact.
        #expect(opened.allSatisfy { $0.confidence == .inferred })

        await provider.ingest(GenericWebhookReport(identifier: "aider", activity: .ended))
        let ended = await collector.wait(for: 3)
        #expect(ended.last?.activity == .ended)
        await collector.stop()
    }

    @Test("Removing a target ends the session it owned")
    func removingATargetEndsItsSession() async throws {
        let target = GenericTarget(displayName: "Aider", webhookIdentifier: "aider")
        let provider = GenericProvider(targets: [target])
        let collector = SignalCollector()
        await collector.attach(to: await provider.signals)

        await provider.ingest(GenericWebhookReport(identifier: "aider", activity: .working))
        #expect(await collector.wait(for: 1).count == 1)
        await provider.configure([])
        let signals = await collector.wait(for: 2)
        #expect(signals.last?.activity == .ended)
        await collector.stop()
    }
}
