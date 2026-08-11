import Foundation
import Testing
import VigilCore
import VigilSupport

@testable import VigilProviders

@Suite("Tier C: work that leaves no trace in the transcript", .serialized)
struct AgentChildrenTests {
    private let scratch = TranscriptScratch()

    private func provider() -> ClaudeCodeProvider {
        ClaudeCodeProvider(configuration: scratch.configuration, access: DirectFileAccess())
    }

    private func collector(on provider: ClaudeCodeProvider) async -> SignalCollector {
        let collector = SignalCollector()
        await collector.attach(to: await provider.signals)
        return collector
    }

    /// Risk R6, caught in the wild: a session whose last transcript record was
    /// `end_turn` eight minutes earlier still had a live `/bin/zsh` child — the
    /// build it had backgrounded and was waiting on. Declaring that idle lets the
    /// Mac sleep out from under a job that is still running.
    @Test("A quiet session with a running child keeps reporting work")
    func busyChildKeepsSessionAwake() async {
        let start = Date()
        let url = scratch.transcript(
            "waiting", lines: [TranscriptScratch.record("assistant", stop: "end_turn")])
        scratch.processFile(pid: 9001, session: "waiting", cwd: "/Volumes/Work/Build")
        let provider = self.provider()
        let collector = await self.collector(on: provider)
        await provider.ingest(url, now: start)

        // The turn really did end, so Tier A settles on idle and stays there.
        await provider.sweepForIdle(now: start.addingTimeInterval(600))
        #expect(await collector.settle().map(\.activity) == [.idle])

        // The child is the only thing that knows the work continues.
        await provider.sweepForDeadProcesses(
            now: start.addingTimeInterval(610), isAlive: { _ in true }, busyPids: { _ in [9001] })
        #expect(await collector.wait(for: 2).map(\.activity) == [.idle, .working])
        await collector.stop()
    }

    /// The rule `docs/03` Tier C insists on, and the new signal must not break
    /// it: the agent merely being alive is not work. Only a child of it is.
    @Test("A live process with no children never reports work on its own")
    func liveProcessAloneIsNotWork() async {
        let start = Date()
        let url = scratch.transcript(
            "quiet", lines: [TranscriptScratch.record("assistant", stop: "end_turn")])
        scratch.processFile(pid: 9002, session: "quiet", cwd: "/Volumes/Work/Quiet")
        let provider = self.provider()
        let collector = await self.collector(on: provider)
        await provider.ingest(url, now: start)
        await provider.sweepForIdle(now: start.addingTimeInterval(600))
        #expect(await collector.settle().map(\.activity) == [.idle])

        for tick in 1...6 {
            await provider.sweepForDeadProcesses(
                now: start.addingTimeInterval(600 + Double(tick) * 15),
                isAlive: { _ in true }, busyPids: { _ in [] })
        }
        #expect(await collector.settle().map(\.activity) == [.idle])
        await collector.stop()
    }

    /// A failed `sysctl` must mean "ask again later", never "nothing is running".
    @Test("An unreadable process table does not resurrect or end anything")
    func unreadableProcessTableIsIgnored() async {
        let start = Date()
        let url = scratch.transcript(
            "unknown", lines: [TranscriptScratch.record("assistant", stop: "end_turn")])
        scratch.processFile(pid: 9003, session: "unknown", cwd: "/Volumes/Work/Unknown")
        let provider = self.provider()
        let collector = await self.collector(on: provider)
        await provider.ingest(url, now: start)
        await provider.sweepForIdle(now: start.addingTimeInterval(600))
        #expect(await collector.settle().map(\.activity) == [.idle])

        await provider.sweepForDeadProcesses(
            now: start.addingTimeInterval(615), isAlive: { _ in true }, busyPids: { _ in nil })
        #expect(await collector.settle().map(\.activity) == [.idle])
        await collector.stop()
    }

}
