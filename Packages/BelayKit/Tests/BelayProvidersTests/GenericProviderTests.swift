import BelayCore
import BelaySupport
import Foundation
import Testing

@testable import BelayProviders

@Suite("GenericProvider")
struct GenericProviderTests {
    private let scratch = GenericScratch()

    private func collector(on provider: GenericProvider) async -> SignalCollector {
        let collector = SignalCollector()
        await collector.attach(to: await provider.signals)
        return collector
    }

    /// FSEvents needs a moment between `FSEventStreamStart` and the first write,
    /// or the write lands before the stream is listening and the test is a coin
    /// flip. The Claude Code end-to-end test pays the same 400 ms.
    private func settleWatchers() async {
        try? await Task.sleep(nanoseconds: 400_000_000)
    }

    private func target(
        _ name: String, folder: URL?, process: String? = nil, webhook: String? = nil
    ) -> GenericTarget {
        GenericTarget(
            displayName: name,
            watchedFolder: folder,
            processName: process,
            webhookIdentifier: webhook,
            latency: 0.1)
    }

    @Test("A change under a watched folder is work, and the quiet period ends it")
    func folderChangeThenQuiet() async throws {
        let folder = scratch.folder("aider-project")
        let clock = SteppedClock()
        let provider = GenericProvider(targets: [target("Aider", folder: folder)], clock: clock)
        let collector = await self.collector(on: provider)

        try await provider.start()
        await settleWatchers()
        scratch.write("hello", to: "chat.md", in: folder)
        let started = await collector.wait(for: 1, timeout: 6)
        #expect(started.first?.activity == .working)
        #expect(started.first?.provider == .generic)
        #expect(started.first?.confidence == .inferred)
        #expect(started.first?.workspace == "Aider")

        clock.advance(120)
        await provider.sweepForIdle(now: clock.now)
        let finished = await collector.wait(for: 2, timeout: 6)
        #expect(finished.last?.activity == .idle)

        await provider.stop()
        await collector.stop()
    }

    @Test("A folder nobody touches never claims work")
    func silentFolderStaysSilent() async throws {
        let provider = GenericProvider(targets: [target("Quiet", folder: scratch.folder("quiet"))])
        let collector = await self.collector(on: provider)

        try await provider.start()
        await settleWatchers()
        for _ in 0..<3 { await provider.tick() }
        #expect(await collector.settle().isEmpty)

        await provider.stop()
        await collector.stop()
    }

    @Test("A live process on its own is context, never work")
    func processAliveIsNotWork() async throws {
        let roster = RosterBox(["aider"])
        let provider = GenericProvider(
            targets: [target("Aider", folder: scratch.folder("aider"), process: "aider")],
            roster: roster.scan)
        let collector = await self.collector(on: provider)

        try await provider.start()
        await settleWatchers()
        // Every sweep the provider has, run repeatedly, with the process present
        // the whole time: docs/03 Tier C says none of this may produce `.working`.
        for _ in 0..<6 { await provider.tick() }
        #expect(await collector.settle().isEmpty)

        await provider.stop()
        await collector.stop()
    }

    @Test("A folder change while the named process is gone is not that agent")
    func changeWithoutProcessIsIgnored() async throws {
        let folder = scratch.folder("orphan")
        let provider = GenericProvider(
            targets: [target("Aider", folder: folder, process: "aider")],
            roster: RosterBox([]).scan)
        let collector = await self.collector(on: provider)

        try await provider.start()
        await settleWatchers()
        scratch.write("build output", to: "artifact.o", in: folder)
        #expect(await collector.settle().isEmpty)

        await provider.stop()
        await collector.stop()
    }

    @Test("A process that exits ends its session")
    func deadProcessExpiresSession() async throws {
        let folder = scratch.folder("codex")
        let roster = RosterBox(["codex"])
        let clock = SteppedClock()
        let provider = GenericProvider(
            targets: [target("Codex CLI", folder: folder, process: "codex")],
            clock: clock,
            roster: roster.scan)
        let collector = await self.collector(on: provider)

        try await provider.start()
        await settleWatchers()
        scratch.write("rollout", to: "session.jsonl", in: folder)
        #expect(await collector.wait(for: 1, timeout: 6).first?.activity == .working)

        roster.set([])
        clock.advance(20)
        await provider.sweepForDeadProcesses(now: clock.now)
        let signals = await collector.wait(for: 2, timeout: 6)
        #expect(signals.last?.activity == .ended)

        await provider.stop()
        await collector.stop()
    }

    @Test("A target-less webhook watch is retired once it has been quiet too long")
    func targetlessWebhookIsRetired() async throws {
        let clock = SteppedClock()
        let provider = GenericProvider(targets: [], clock: clock)
        let collector = await self.collector(on: provider)
        try await provider.start()

        // A hook posting a per-run identifier that matches no configured target.
        await provider.ingest(
            GenericWebhookReport(identifier: "aider-1234", activity: .working), at: clock.now)
        #expect(await collector.wait(for: 1).first?.activity == .working)

        // Long past the retire horizon with nothing more from it.
        clock.advance(11 * 60)
        await provider.sweepForIdle(now: clock.now)
        // It idled and then was retired, not left in the dict forever.
        let activities = await collector.wait(for: 3).map(\.activity)
        #expect(activities.contains(.ended))

        await provider.stop()
        await collector.stop()
    }

    @Test("Targets share one timer, and one stream per distinct folder")
    func watchersShareTimers() async throws {
        let shared = scratch.folder("shared")
        let other = scratch.folder("other")
        let provider = GenericProvider(targets: [
            target("One", folder: shared),
            target("Two", folder: shared),
            target("Three", folder: other),
            target("Webhook only", folder: nil, webhook: "four")
        ])

        try await provider.start()
        #expect(await provider.timerCount == 1)
        #expect(await provider.streamCount == 2)
        #expect(await provider.isWatching)

        await provider.stop()
    }

    @Test("Stopping leaves no stream and no timer behind")
    func teardownIsComplete() async throws {
        let provider = GenericProvider(targets: [target("One", folder: scratch.folder("one"))])
        try await provider.start()
        await provider.stop()

        #expect(await provider.timerCount == 0)
        #expect(await provider.streamCount == 0)
        #expect(await provider.isWatching == false)
    }

    /// The one part of Tier C that talks to the kernel. If `sysctl` ever stops
    /// answering under the sandbox, this is the test that says so.
    @Test("The process roster sees this very process, and invents nothing")
    func rosterReadsTheRealProcessTable() {
        let roster = ProcessRoster.scan() ?? []
        #expect(!roster.isEmpty)
        let own = String(ProcessInfo.processInfo.processName.prefix(ProcessRoster.commandNameLimit))
        #expect(ProcessRoster.contains(own, in: roster))
        #expect(ProcessRoster.contains("no-such-agent-\(UUID().uuidString)", in: roster) == false)
        #expect(ProcessRoster.contains("", in: roster) == false)
    }

    @Test("Availability describes what the user still has to do")
    func availabilityReflectsConfiguration() async throws {
        #expect(await GenericProvider().availability != .ready)

        let missing = scratch.root.appendingPathComponent("gone-\(UUID().uuidString)")
        let blind = GenericProvider(targets: [target("Missing", folder: missing)])
        guard case .needsSetup(let text) = await blind.availability else {
            Issue.record("expected needsSetup for an unreadable folder")
            return
        }
        // A folder that does not exist is described as absent, never as a
        // permission to grant: the words send the user to the actual fix.
        #expect(text.contains("yet"), "missing folder read as a permission problem: \(text)")
        let ready = GenericProvider(targets: [target("Fine", folder: scratch.folder("fine"))])
        #expect(await ready.availability == .ready)
    }

    /// "~/.codex/sessions", not "sessions": the badge has to say which tool
    /// it is even talking about.
    @Test("The badge names the folder by its abbreviated path")
    func badgeAbbreviatesTheHomePath() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let inside = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        #expect(GenericProvider.abbreviated(inside) == "~/.codex/sessions")
        let outside = URL(fileURLWithPath: "/Library/Caches/agent")
        #expect(GenericProvider.abbreviated(outside) == "/Library/Caches/agent")
    }
}
