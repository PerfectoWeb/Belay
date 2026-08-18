import BelayCore
import BelaySupport
import Foundation
import Testing

@testable import BelayProviders

/// The retry bugs of 2026-08-18: a turn waiting on the API is silent for
/// minutes, and the record that silence ends in reads like a finished turn.
/// docs/DISCOVERY §2.3.
@Suite("ClaudeCodeProvider retries")
struct ClaudeCodeRetryTests {
    private let scratch = TranscriptScratch()

    private func provider() -> ClaudeCodeProvider {
        ClaudeCodeProvider(configuration: scratch.configuration, access: DirectFileAccess())
    }

    private func collector(on provider: ClaudeCodeProvider) async -> SignalCollector {
        let collector = SignalCollector()
        await collector.attach(to: await provider.signals)
        return collector
    }

    @Test("A turn waiting on the API outlives the idle horizon")
    func awaitingAssistantGrace() async {
        let start = Date()
        // The tail is a user record: a prompt went out and the API never
        // answered. This is the "Model overloaded · retrying" screenshot —
        // minutes of silence exactly when the run most needs the Mac awake.
        let url = scratch.transcript("retrying", lines: [TranscriptScratch.record("user")])
        let provider = self.provider()
        let collector = await self.collector(on: provider)
        await provider.ingest(url, now: start)

        // Past the idle horizon: still working, and said again so the
        // coordinator's TTL sees a fresh signal rather than evicting mid-retry.
        await provider.sweepForIdle(now: start.addingTimeInterval(46))
        await provider.sweepForIdle(now: start.addingTimeInterval(400))
        let held = await collector.wait(for: 3)
        #expect(held.map(\.activity) == [.working, .working, .working])

        // The grace is a budget, not a promise: past it, Belay is guessing.
        await provider.sweepForIdle(now: start.addingTimeInterval(15 * 60 + 1))
        let signals = await collector.wait(for: 4)
        #expect(signals.map(\.activity) == [.working, .working, .working, .idle])
        await collector.stop()
    }

    @Test("An API-error record keeps the turn alive instead of finishing it")
    func apiErrorRecordKeepsWorking() async {
        let start = Date()
        let url = scratch.transcript("overloaded", lines: [TranscriptScratch.record("user")])
        let provider = self.provider()
        let collector = await self.collector(on: provider)
        await provider.ingest(url, now: start)

        // Four minutes on, the CLI gives up one attempt and writes the error
        // record. Its stop_reason alone would read as a finished turn — idle —
        // and the hold would drop at the worst moment.
        scratch.append(TranscriptScratch.apiErrorRecord() + "\n", to: url)
        await provider.ingest(url, now: start.addingTimeInterval(240))

        let signals = await collector.wait(for: 2)
        #expect(signals.map(\.activity) == [.working, .working])

        // And the answer finally arriving still ends the turn normally.
        scratch.append(TranscriptScratch.record("assistant", stop: "end_turn") + "\n", to: url)
        await provider.ingest(url, now: start.addingTimeInterval(300))
        let finished = await collector.wait(for: 3)
        #expect(finished.map(\.activity) == [.working, .working, .idle])
        await collector.stop()
    }

    @Test("An interrupted turn still decays: the grace is not a promise to wait")
    func interruptedTurnStillDecays() async {
        let start = Date()
        // Escape writes a user record too, so the flag stays up — the cost is
        // bounded by the grace, and a user who pressed Escape is at the
        // keyboard, where idle sleep was not imminent anyway.
        let url = scratch.transcript("escaped", lines: [TranscriptScratch.record("user")])
        let provider = self.provider()
        let collector = await self.collector(on: provider)
        await provider.ingest(url, now: start)

        await provider.sweepForIdle(now: start.addingTimeInterval(16 * 60))
        let signals = await collector.wait(for: 2)
        #expect(signals.map(\.activity) == [.working, .idle])
        await collector.stop()
    }
}
