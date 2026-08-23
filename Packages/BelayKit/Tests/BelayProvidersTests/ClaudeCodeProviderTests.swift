import BelayCore
import BelaySupport
import Foundation
import Testing

@testable import BelayProviders

@Suite("ClaudeCodeProvider")
struct ClaudeCodeProviderTests {
    private let scratch = TranscriptScratch()

    private func provider() -> ClaudeCodeProvider {
        ClaudeCodeProvider(configuration: scratch.configuration, access: DirectFileAccess())
    }

    private func collector(on provider: ClaudeCodeProvider) async -> SignalCollector {
        let collector = SignalCollector()
        await collector.attach(to: await provider.signals)
        return collector
    }

    @Test("Availability follows readability of ~/.claude/projects")
    func availability() async throws {
        #expect(await provider().availability == .ready)

        // A folder the build cannot read — the sandbox before a grant — is
        // a permission problem and says so.
        let blind = ClaudeCodeProvider(configuration: scratch.configuration, access: DeniedFileAccess())
        guard case .needsSetup = await blind.availability else {
            Issue.record("expected needsSetup when the folder is unreadable")
            return
        }
        await #expect(throws: ProviderError.self) { try await blind.start() }

        // A folder that is simply not there, seen by a build that can tell,
        // is "not installed": a fact to report, not a grant to ask for. The
        // first tester without Codex was asked for ~/.codex by the old rule.
        let absent = ClaudeCodeProvider.Configuration(
            projectsDirectory: URL(fileURLWithPath: "/nope-\(UUID().uuidString)/projects"),
            sessionsDirectory: scratch.sessions)
        let missing = ClaudeCodeProvider(configuration: absent)
        guard case .unavailable = await missing.availability else {
            Issue.record("expected unavailable when the folder does not exist")
            return
        }
    }

    @Test("Old transcripts are seeded at EOF and stay silent at launch")
    func staleTranscriptsAreIgnoredAtStartup() async {
        for index in 0..<12 {
            let url = scratch.transcript(
                "old-\(index)",
                lines: [
                    TranscriptScratch.record("assistant", stop: "tool_use"),
                    #"{"type":"last-prompt","leafUuid":"x"}"#
                ])
            scratch.touch(url, secondsAgo: 3_600)
        }
        let provider = self.provider()
        let collector = await self.collector(on: provider)
        await provider.seedExistingTranscripts()
        #expect(await collector.settle().isEmpty)
        await collector.stop()
    }

    @Test("A transcript written seconds ago is a live turn")
    func freshTranscriptAtStartup() async {
        scratch.transcript("fresh", lines: [TranscriptScratch.record("assistant", stop: "tool_use")])
        let provider = self.provider()
        let collector = await self.collector(on: provider)
        await provider.seedExistingTranscripts()

        let signals = await collector.wait(for: 1)
        #expect(signals.count == 1)
        #expect(signals.first?.activity == .working)
        #expect(signals.first?.confidence == .inferred)
        #expect(signals.first?.session == SessionID("fresh"))
        #expect(signals.first?.workspace == "project")
        await collector.stop()
    }

    @Test("A transcript that appears while running starts a session")
    func newTranscriptAtRuntime() async {
        let provider = self.provider()
        let collector = await self.collector(on: provider)
        let url = scratch.transcript(
            "live", lines: [TranscriptScratch.record("assistant", stop: "tool_use")])
        await provider.ingest(url, now: Date())

        let signals = await collector.wait(for: 1)
        #expect(signals.map(\.activity) == [.working])
        await collector.stop()
    }

    @Test("A completed turn followed by metadata still reads as idle")
    func metadataTailDoesNotHideTheTurn() async {
        let start = Date()
        let url = scratch.transcript(
            "turn", lines: [TranscriptScratch.record("assistant", stop: "tool_use")])
        let provider = self.provider()
        let collector = await self.collector(on: provider)
        await provider.ingest(url, now: start)

        scratch.append(
            TranscriptScratch.record("assistant", stop: "end_turn") + "\n"
                + #"{"type":"last-prompt","leafUuid":"x"}"# + "\n"
                + #"{"type":"mode","mode":"default"}"# + "\n",
            to: url)
        await provider.ingest(url, now: start.addingTimeInterval(2))

        let signals = await collector.wait(for: 2)
        #expect(signals.map(\.activity) == [.working, .idle])
        await collector.stop()
    }

    @Test("Growth nobody can parse is still activity")
    func unparseableGrowthIsWorking() async {
        let start = Date()
        let url = scratch.transcript("garbage", lines: [TranscriptScratch.record("user")])
        let provider = self.provider()
        let collector = await self.collector(on: provider)
        await provider.ingest(url, now: start)
        scratch.append("<<< not json, not even close >>>\n", to: url)
        await provider.ingest(url, now: start.addingTimeInterval(1))

        let signals = await collector.wait(for: 2)
        #expect(signals.map(\.activity) == [.working, .working])
        await collector.stop()
    }

    @Test("No growth for inferredIdleAfter ends the turn")
    func idleSweep() async {
        let start = Date()
        let url = scratch.transcript(
            "quiet", lines: [TranscriptScratch.record("assistant", stop: "tool_use")])
        let provider = self.provider()
        let collector = await self.collector(on: provider)
        await provider.ingest(url, now: start)

        // docs/DISCOVERY §2.2: a real tool call went ten seconds without a byte.
        await provider.sweepForIdle(now: start.addingTimeInterval(10))
        #expect(await collector.settle().map(\.activity) == [.working])

        await provider.sweepForIdle(now: start.addingTimeInterval(46))
        let signals = await collector.wait(for: 2)
        #expect(signals.map(\.activity) == [.working, .idle])

        // Idle does not repeat once reported.
        await provider.sweepForIdle(now: start.addingTimeInterval(200))
        #expect(await collector.settle().count == 2)
        await collector.stop()
    }

    @Test("A dead process ends its session without waiting for the TTL")
    func deadProcessEndsSession() async {
        let start = Date()
        let url = scratch.transcript(
            "zombie", lines: [TranscriptScratch.record("assistant", stop: "tool_use")])
        scratch.processFile(pid: 4321, session: "zombie", cwd: "/Volumes/Work/Demo")
        let provider = self.provider()
        let collector = await self.collector(on: provider)
        await provider.ingest(url, now: start)

        await provider.sweepForDeadProcesses(now: start.addingTimeInterval(15), isAlive: { _ in true })
        #expect(await collector.settle().map(\.activity) == [.working])

        await provider.sweepForDeadProcesses(now: start.addingTimeInterval(30), isAlive: { _ in false })
        let signals = await collector.wait(for: 2)
        #expect(signals.map(\.activity) == [.working, .ended])
        // Tier C also supplies the real cwd, which beats the lossy directory name.
        #expect(signals.last?.workspace == "Demo")
        await collector.stop()
    }

    @Test("A deleted transcript ends its session")
    func deletedTranscriptEndsSession() async {
        let start = Date()
        let url = scratch.transcript("gone", lines: [TranscriptScratch.record("user")])
        let provider = self.provider()
        let collector = await self.collector(on: provider)
        await provider.ingest(url, now: start)
        try? FileManager.default.removeItem(at: url)
        await provider.ingest(url, now: start.addingTimeInterval(1))

        let signals = await collector.wait(for: 2)
        #expect(signals.map(\.activity) == [.working, .ended])
        await collector.stop()
    }

    @Test("Two concurrent sessions are tracked independently")
    func concurrentSessions() async {
        let start = Date()
        let one = scratch.transcript(
            "one", project: "-a-one", lines: [TranscriptScratch.record("assistant", stop: "tool_use")])
        let two = scratch.transcript(
            "two", project: "-b-two", lines: [TranscriptScratch.record("assistant", stop: "end_turn")])
        let provider = self.provider()
        let collector = await self.collector(on: provider)
        await provider.ingest(one, now: start)
        await provider.ingest(two, now: start)

        let signals = await collector.wait(for: 1)
        // "one" announces; "two" opens on a finished turn and is followed
        // silently — an idle first word is not news (see `report`).
        #expect(signals.map(\.session) == [SessionID("one")])
        #expect(signals.first?.activity == .working)
        #expect(signals.first?.workspace == "one")
        #expect(await provider.watched[SessionID("two")]?.reported == .idle)
        await collector.stop()
    }

    @Test("start() watches for real: a live write becomes a signal")
    func endToEndThroughFSEvents() async throws {
        let provider = self.provider()
        let collector = await self.collector(on: provider)
        try await provider.start()
        defer { Task { await provider.stop() } }

        try await Task.sleep(nanoseconds: 400_000_000)
        let url = scratch.transcript(
            "e2e", lines: [TranscriptScratch.record("assistant", stop: "tool_use")])
        scratch.append(TranscriptScratch.record("user") + "\n", to: url)

        let signals = await collector.wait(for: 1, timeout: 6)
        #expect(signals.first?.activity == .working)
        #expect(signals.first?.session == SessionID("e2e"))
        await collector.stop()
    }

    @Test("stop() releases the watcher and the timer")
    func stopTearsDown() async throws {
        let provider = self.provider()
        try await provider.start()
        await provider.stop()
        #expect(await provider.isWatching == false)
        // Starting again after a stop must be safe.
        try await provider.start()
        await provider.stop()
    }
}
