import Foundation
import Testing
import VigilCore
import VigilSupport

@testable import VigilProviders

/// Tier A and Tier C, where they used to argue.
///
/// Split from `ClaudeCodeProviderTests` only because that file is at the length
/// the linter allows. See PROJECT_STATE D26.
@Suite("Claude Code tiers agree")
struct ClaudeCodeTierAgreementTests {
    private let scratch = TranscriptScratch()

    private func provider() -> ClaudeCodeProvider {
        ClaudeCodeProvider(configuration: scratch.configuration, access: DirectFileAccess())
    }

    private func collector(on provider: ClaudeCodeProvider) async -> SignalCollector {
        let collector = SignalCollector()
        await collector.attach(to: await provider.signals)
        return collector
    }

    /// A long tool call writes nothing to the transcript, so Tier A idles it
    /// and Tier C revives it from a running child. The two used to argue: Tier C
    /// reported working without moving anything the idle sweep reads, so five
    /// seconds later the sweep put it back to idle, and the panel flipped
    /// working, idle, working every fifteen seconds for the whole call.
    @Test("Tier C's proof of a running tool survives the idle sweep")
    func busyChildIsNotUndoneByTheIdleSweep() async {
        let start = Date()
        let url = scratch.transcript(
            "toolcall", lines: [TranscriptScratch.record("assistant", stop: "tool_use")])
        scratch.processFile(pid: 4321, session: "toolcall", cwd: "/Volumes/Work/Demo")
        let provider = self.provider()
        let collector = await self.collector(on: provider)
        await provider.ingest(url, now: start)
        #expect(await collector.settle().map(\.activity) == [.working])

        // Well past the no-growth horizon, with a child that started just now.
        let late = start.addingTimeInterval(120)
        await provider.sweepForDeadProcesses(
            now: late, isAlive: { _ in true }, busyPids: { pids, _, _ in pids })
        await provider.sweepForIdle(now: late.addingTimeInterval(5))

        // The whole sequence, not a count: `report` re-emits `.working` as a
        // heartbeat, so waiting for "two signals" and reading the last one is a
        // race with the stream's own pump — which is how this test was written
        // first, and it lost that race fourteen runs out of fifteen.
        let signals = await collector.wait(for: 2)
        #expect(signals.map(\.activity) == [.working, .working])
        #expect(await collector.settle().map(\.activity) == [.working, .working])
        await collector.stop()
    }
}
