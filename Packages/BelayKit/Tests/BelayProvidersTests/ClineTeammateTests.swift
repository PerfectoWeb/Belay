import BelayCore
import BelaySupport
import Foundation
import Testing

@testable import BelayProviders

/// Cline's team mode: teammates are messages files inside the parent's
/// directory, tracked as sessions of their own and presented under the
/// parent, the way Claude Code's subagents are.
@Suite("Cline teammates")
struct ClineTeammateTests {
    private let scratch = ClineScratch()

    private func provider() -> ClineProvider {
        ClineProvider(configuration: scratch.configuration, access: DirectFileAccess())
    }

    private func teammateFile(_ session: String, stem: String, bytes: Int) {
        let url = scratch.sessions.appendingPathComponent(session, isDirectory: true)
            .appendingPathComponent("\(stem).messages.json")
        try? Data(String(repeating: "x", count: bytes).utf8).write(to: url)
    }

    @Test("A teammate file becomes a child session under its parent")
    func teammateAppears() async throws {
        let provider = provider()
        try await provider.start()
        scratch.session("s1", status: "running")
        await provider.ingest("s1", now: Date())

        teammateFile("s1", stem: "hardening-agent__aB3xYz", bytes: 100)
        await provider.ingestTeammate(
            session: "s1", stem: "hardening-agent__aB3xYz", agent: "hardening-agent", now: Date())

        let mate = await provider.watched[SessionID("hardening-agent__aB3xYz")]
        #expect(mate?.parent == SessionID("s1"))
        #expect(mate?.kind == "hardening-agent")
        #expect(mate?.reported == .working)
        #expect(mate?.workspace == "demo", "the parent's workspace carries over")
        await provider.stop()
    }

    @Test("Growth keeps a teammate working; the parent's end ends it")
    func lifecycle() async throws {
        let provider = provider()
        try await provider.start()
        scratch.session("s2", status: "running")
        await provider.ingest("s2", now: Date())
        teammateFile("s2", stem: "tester__q1", bytes: 50)
        let start = Date()
        await provider.ingestTeammate(session: "s2", stem: "tester__q1", agent: "tester", now: start)

        // Quiet teammate goes idle on the sweep.
        await provider.sweepForIdle(now: start.addingTimeInterval(90))
        #expect(await provider.watched[SessionID("tester__q1")]?.reported == .idle)

        // Growth wakes it.
        teammateFile("s2", stem: "tester__q1", bytes: 500)
        await provider.ingestTeammate(
            session: "s2", stem: "tester__q1", agent: "tester",
            now: start.addingTimeInterval(100))
        #expect(await provider.watched[SessionID("tester__q1")]?.reported == .working)

        // Parent completes: the teammate goes with it.
        scratch.session("s2", status: "completed")
        await provider.ingest("s2", now: start.addingTimeInterval(120))
        #expect(await provider.watched[SessionID("tester__q1")] == nil)
        #expect(await provider.watched[SessionID("s2")] == nil)
        await provider.stop()
    }

    /// Growth is a teammate's only signal, so a truncation (context compaction,
    /// checkpoint restore) must count as a write too — otherwise a working
    /// teammate whose file shrank goes dark until it re-exceeds its old peak,
    /// which may be never.
    @Test("A teammate whose file is truncated is not left dark")
    func truncationStillCountsAsAWrite() async throws {
        let provider = provider()
        try await provider.start()
        scratch.session("s4", status: "running")
        await provider.ingest("s4", now: Date())
        let start = Date()
        teammateFile("s4", stem: "builder__z9", bytes: 800)
        await provider.ingestTeammate(
            session: "s4", stem: "builder__z9", agent: "builder", now: start)
        #expect(await provider.watched[SessionID("builder__z9")]?.reported == .working)

        await provider.sweepForIdle(now: start.addingTimeInterval(90))
        #expect(await provider.watched[SessionID("builder__z9")]?.reported == .idle)

        // Compacted to a smaller size: the shrink wakes it rather than being
        // swallowed as "not bigger than the old maximum".
        teammateFile("s4", stem: "builder__z9", bytes: 100)
        await provider.ingestTeammate(
            session: "s4", stem: "builder__z9", agent: "builder",
            now: start.addingTimeInterval(100))
        #expect(await provider.watched[SessionID("builder__z9")]?.reported == .working)
        await provider.stop()
    }

    @Test("Existing teammates are seeded when their session is adopted")
    func seededWithParent() async throws {
        scratch.session("s3", status: "running")
        teammateFile("s3", stem: "data-agent__zz", bytes: 200)
        let provider = provider()
        try await provider.start()
        let mate = await provider.watched[SessionID("data-agent__zz")]
        #expect(mate != nil)
        #expect(mate?.parent == SessionID("s3"))
        await provider.stop()
    }

    @Test("Changed teammate paths route to the teammate, not the root")
    func pathRouting() {
        let root = scratch.sessions
        let mate = ClineSessions.teammate(
            of: root.path + "/abc/hardening-agent__iXh40Z.messages.json", sessionID: "abc")
        #expect(mate?.stem == "hardening-agent__iXh40Z")
        #expect(mate?.agent == "hardening-agent")
        #expect(ClineSessions.teammate(of: root.path + "/abc/abc.messages.json", sessionID: "abc") == nil)
        #expect(ClineSessions.teammate(of: root.path + "/abc/abc.json", sessionID: "abc") == nil)
    }
}
