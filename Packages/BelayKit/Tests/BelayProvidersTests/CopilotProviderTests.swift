import BelayCore
import BelaySupport
import Foundation
import Testing

@testable import BelayProviders

@Suite("Copilot events")
struct CopilotEventsTests {
    @Test("Turn markers map to edges, last one wins, noise maps to nothing")
    func markers() {
        let open = CopilotEvents.verdict(in: [CopilotScratch.line("assistant.turn_start")])
        #expect(open == .init(activity: .working, turnOpen: true))
        let closed = CopilotEvents.verdict(
            in: [
                CopilotScratch.line("assistant.turn_start"),
                CopilotScratch.line("assistant.turn_end")
            ])
        #expect(closed == .init(activity: .idle, turnOpen: false))
        #expect(CopilotEvents.verdict(in: [CopilotScratch.line("session.usage_checkpoint")]) == nil)
        #expect(CopilotEvents.verdict(in: ["not json at all"]) == nil)
    }

    @Test("The workspace is the last path component of session.start's cwd")
    func workspace() {
        let lines = [CopilotScratch.start(cwd: "/Users/x/Work/MyProject")]
        #expect(CopilotEvents.workspace(in: lines) == "MyProject")
        #expect(CopilotEvents.workspace(in: [CopilotScratch.line("assistant.turn_start")]) == nil)
    }

    @Test("Only events.jsonl counts, and the session id is its directory")
    func naming() {
        let url = URL(fileURLWithPath: "/a/session-state/uuid-1/events.jsonl")
        #expect(CopilotEvents.isEventsFile(url))
        #expect(!CopilotEvents.isEventsFile(URL(fileURLWithPath: "/a/uuid-1/plan.md")))
        #expect(CopilotEvents.sessionID(for: url) == SessionID("uuid-1"))
    }
}

@Suite("CopilotProvider")
struct CopilotProviderTests {
    private let scratch = CopilotScratch()

    private func provider() -> CopilotProvider {
        CopilotProvider(configuration: scratch.configuration, access: DirectFileAccess())
    }

    @Test("Availability distinguishes missing sessions from missing access")
    func availability() async throws {
        #expect(await provider().availability == .ready)

        let noSessions = CopilotProvider.Configuration(
            sessionsDirectory: scratch.root.appendingPathComponent("gone", isDirectory: true))
        let waiting = CopilotProvider(configuration: noSessions)
        guard case .unavailable = await waiting.availability else {
            Issue.record("expected unavailable while ~/.copilot/session-state does not exist")
            return
        }

        let blind = CopilotProvider(configuration: noSessions, access: DeniedFileAccess())
        guard case .needsSetup = await blind.availability else {
            Issue.record("expected needsSetup when nothing is readable")
            return
        }
    }

    @Test("A live session is adopted, classified, and idles on its marker")
    func adoptAndClose() async throws {
        let url = scratch.events(
            "s1",
            lines: [
                CopilotScratch.start(cwd: "/tmp/demo"),
                CopilotScratch.line("assistant.turn_start")
            ])
        let provider = provider()
        try await provider.start()

        await provider.ingest(url, now: Date())
        let open = await provider.watched[SessionID("s1")]
        #expect(open?.turnOpen == true)
        #expect(open?.reported == .working)
        #expect(open?.workspace == "demo")

        scratch.append([CopilotScratch.line("assistant.turn_end")], to: url)
        await provider.ingest(url, now: Date())
        let closed = await provider.watched[SessionID("s1")]
        #expect(closed?.turnOpen == false)
        #expect(closed?.reported == .idle)
        await provider.stop()
    }

    @Test("session.shutdown ends the session outright")
    func shutdownEnds() async throws {
        let url = scratch.events("s2", lines: [CopilotScratch.line("assistant.turn_start")])
        let provider = provider()
        try await provider.start()
        await provider.ingest(url, now: Date())
        #expect(await provider.watched[SessionID("s2")]?.reported == .working)

        scratch.append(
            [CopilotScratch.line("assistant.turn_end"), CopilotScratch.line("session.shutdown")],
            to: url)
        await provider.ingest(url, now: Date())
        #expect(await provider.watched[SessionID("s2")] == nil)
        await provider.stop()
    }

    @Test("Old sessions stay silent at launch; fresh ones are classified")
    func startupSeeding() async throws {
        let old = scratch.events("s-old", lines: [CopilotScratch.line("assistant.turn_end")])
        scratch.touch(old, secondsAgo: 3_600)
        _ = scratch.events("s-fresh", lines: [CopilotScratch.line("assistant.turn_start")])

        let provider = provider()
        try await provider.start()
        #expect(await provider.watched[SessionID("s-old")] == nil)
        let live = await provider.watched[SessionID("s-fresh")]
        #expect(live?.reported == .working)
        #expect(live?.turnOpen == true)
        await provider.stop()
    }

    @Test("A finished tail is followed but never announced")
    func idleFirstStaysSilent() async throws {
        let url = scratch.events(
            "s3",
            lines: [
                CopilotScratch.line("assistant.turn_start"),
                CopilotScratch.line("assistant.turn_end")
            ])
        let provider = provider()
        try await provider.start()
        await provider.ingest(url, now: Date())
        #expect(await provider.watched[SessionID("s3")]?.reported == .idle)

        // A real turn in the same file still announces normally.
        scratch.append([CopilotScratch.line("assistant.turn_start")], to: url)
        await provider.ingest(url, now: Date())
        #expect(await provider.watched[SessionID("s3")]?.reported == .working)
        await provider.stop()
    }

    @Test("Unmarked records prolong a turn but never resurrect a quiet one")
    func metadataNeverResurrects() async throws {
        let url = scratch.events(
            "s4",
            lines: [
                CopilotScratch.line("assistant.turn_start"),
                CopilotScratch.line("assistant.turn_end")
            ])
        let provider = provider()
        try await provider.start()
        await provider.ingest(url, now: Date())
        #expect(await provider.watched[SessionID("s4")]?.reported == .idle)

        scratch.append([CopilotScratch.line("session.usage_checkpoint")], to: url)
        await provider.ingest(url, now: Date())
        #expect(await provider.watched[SessionID("s4")]?.reported == .idle)

        scratch.append([CopilotScratch.line("assistant.turn_start")], to: url)
        await provider.ingest(url, now: Date())
        #expect(await provider.watched[SessionID("s4")]?.reported == .working)
        await provider.stop()
    }

    @Test("A working session ends when no copilot process remains")
    func deadProcessSweep() async throws {
        let url = scratch.events("s5", lines: [CopilotScratch.line("assistant.turn_start")])
        let empty = CopilotProvider(
            configuration: scratch.configuration, access: DirectFileAccess(),
            roster: { [] })
        try await empty.start()
        await empty.ingest(url, now: Date())
        #expect(await empty.watched[SessionID("s5")]?.reported == .working)
        await empty.sweepForDeadProcess(now: Date())
        #expect(await empty.watched[SessionID("s5")] == nil)
        await empty.stop()

        // An unreadable table is "ask again later", never "everything died".
        let blind = CopilotProvider(
            configuration: scratch.configuration, access: DirectFileAccess(),
            roster: { nil })
        try await blind.start()
        let url2 = scratch.events("s6", lines: [CopilotScratch.line("assistant.turn_start")])
        await blind.ingest(url2, now: Date())
        await blind.sweepForDeadProcess(now: Date())
        #expect(await blind.watched[SessionID("s6")] != nil)
        await blind.stop()
    }

    @Test("Silence idles a closed turn but ends an open one only past the grace")
    func idleSweep() async throws {
        let url = scratch.events("s7", lines: [CopilotScratch.line("assistant.turn_start")])
        let provider = provider()
        try await provider.start()
        let now = Date()
        await provider.ingest(url, now: now)

        await provider.sweepForIdle(now: now.addingTimeInterval(120))
        #expect(await provider.watched[SessionID("s7")]?.reported == .working)

        await provider.sweepForIdle(now: now.addingTimeInterval(16 * 60))
        #expect(await provider.watched[SessionID("s7")] == nil)

        let done = scratch.events(
            "s8",
            lines: [
                CopilotScratch.line("assistant.turn_start"),
                CopilotScratch.line("assistant.turn_end")
            ])
        await provider.ingest(done, now: now)
        #expect(await provider.watched[SessionID("s8")]?.reported == .idle)
        await provider.stop()
    }

    @Test("An imported session with old record clocks opens nothing")
    func staleTouchOpensNothing() async throws {
        let provider = provider()
        try await provider.start()
        // Appears at runtime with a fresh mtime, but the records are a month
        // old: a sync tool at work, not a turn.
        let url = scratch.events(
            "s9",
            lines: [
                CopilotScratch.start(cwd: "/tmp/pdd", at: "2026-07-30T10:00:00.000Z"),
                CopilotScratch.line("assistant.turn_start", at: "2026-07-30T10:00:01.000Z")
            ])
        await provider.ingest(url, now: Date())
        #expect(await provider.watched[SessionID("s9")] != nil, "the file is still followed")
        #expect(await provider.watched[SessionID("s9")]?.reported == nil, "but nothing was announced")

        // A real turn in the same file still announces.
        let fresh = ISO8601DateFormatter().string(from: Date())
        scratch.append([CopilotScratch.line("assistant.turn_start", at: fresh)], to: url)
        await provider.ingest(url, now: Date())
        #expect(await provider.watched[SessionID("s9")]?.reported == .working)
        await provider.stop()
    }
}
