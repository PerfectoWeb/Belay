import BelayCore
import BelaySupport
import Foundation
import Testing

@testable import BelayProviders

/// A `~/.codex/sessions` layout on disk, torn down with the suite.
private final class CodexScratch: @unchecked Sendable {
    let root: URL

    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-scratch-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: day, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    var day: URL {
        root.appendingPathComponent("2026/08/20", isDirectory: true)
    }

    var configuration: CodexProvider.Configuration {
        CodexProvider.Configuration(sessionsDirectory: root)
    }

    static func line(_ payloadType: String, type: String = "event_msg") -> String {
        #"{"type":"\#(type)","payload":{"type":"\#(payloadType)"}}"#
    }

    static func meta(cwd: String) -> String {
        #"{"type":"session_meta","payload":{"cwd":"\#(cwd)"}}"#
    }

    func rollout(_ stamp: String, lines: [String]) -> URL {
        let url = day.appendingPathComponent("rollout-\(stamp).jsonl")
        let text = lines.map { $0 + "\n" }.joined()
        try? Data(text.utf8).write(to: url)
        return url
    }

    func append(_ lines: [String], to url: URL) {
        let handle = try? FileHandle(forWritingTo: url)
        try? handle?.seekToEnd()
        try? handle?.write(contentsOf: Data(lines.map { $0 + "\n" }.joined().utf8))
        try? handle?.close()
    }

    func touch(_ url: URL, secondsAgo: TimeInterval) {
        try? FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-secondsAgo)], ofItemAtPath: url.path)
    }
}

@Suite("Codex rollouts")
struct CodexRolloutTests {
    @Test("Markers map to turn edges, aliases included, last one wins")
    func markers() {
        let open = CodexRollout.verdict(in: [CodexScratch.line("task_started")])
        #expect(open == .init(activity: .working, turnOpen: true))
        let closed = CodexRollout.verdict(
            in: [CodexScratch.line("task_started"), CodexScratch.line("task_complete")])
        #expect(closed == .init(activity: .idle, turnOpen: false))
        let alias = CodexRollout.verdict(in: [CodexScratch.line("turn_started")])
        #expect(alias == .init(activity: .working, turnOpen: true))
        #expect(CodexRollout.verdict(in: [CodexScratch.line("token_count")]) == nil)
        #expect(CodexRollout.verdict(in: ["not json at all"]) == nil)
    }

    @Test("The workspace is the last path component of session_meta's cwd")
    func workspace() {
        let lines = [CodexScratch.meta(cwd: "/Users/x/Work/MyProject")]
        #expect(CodexRollout.workspace(in: lines) == "MyProject")
        #expect(CodexRollout.workspace(in: [CodexScratch.line("task_started")]) == nil)
    }

    @Test("Only rollout-*.jsonl files count")
    func naming() {
        #expect(CodexRollout.isRollout(URL(fileURLWithPath: "/a/rollout-2026-x.jsonl")))
        #expect(!CodexRollout.isRollout(URL(fileURLWithPath: "/a/rollout-2026-x.jsonl.zst")))
        #expect(!CodexRollout.isRollout(URL(fileURLWithPath: "/a/notes.jsonl")))
    }
}

@Suite("CodexProvider")
struct CodexProviderTests {
    private let scratch = CodexScratch()

    private func provider() -> CodexProvider {
        CodexProvider(configuration: scratch.configuration, access: DirectFileAccess())
    }

    @Test("Availability distinguishes missing sessions from missing access")
    func availability() async throws {
        #expect(await provider().availability == .ready)

        let noSessions = CodexProvider.Configuration(
            sessionsDirectory: scratch.root.appendingPathComponent("gone", isDirectory: true))
        let waiting = CodexProvider(configuration: noSessions)
        guard case .unavailable = await waiting.availability else {
            Issue.record("expected unavailable while ~/.codex/sessions does not exist")
            return
        }

        let blind = CodexProvider(
            configuration: .init(
                sessionsDirectory: URL(fileURLWithPath: "/nope-\(UUID().uuidString)/sessions")))
        guard case .needsSetup = await blind.availability else {
            Issue.record("expected needsSetup when nothing is readable")
            return
        }
    }

    @Test("A live rollout is adopted, classified, and idles on its marker")
    func adoptAndClose() async throws {
        let url = scratch.rollout(
            "t1-aaaa", lines: [CodexScratch.meta(cwd: "/tmp/demo"), CodexScratch.line("task_started")])
        let provider = provider()
        try await provider.start()

        await provider.ingest(url, now: Date())
        let open = await provider.watched[CodexRollout.sessionID(for: url)]
        #expect(open?.turnOpen == true)
        #expect(open?.reported == .working)
        #expect(open?.workspace == "demo")

        scratch.append([CodexScratch.line("task_complete")], to: url)
        await provider.ingest(url, now: Date())
        let closed = await provider.watched[CodexRollout.sessionID(for: url)]
        #expect(closed?.turnOpen == false)
        #expect(closed?.reported == .idle)
        await provider.stop()
    }

    @Test("Old rollouts stay silent at launch; fresh ones are classified")
    func startupSeeding() async throws {
        let old = scratch.rollout("t2-old", lines: [CodexScratch.line("task_complete")])
        scratch.touch(old, secondsAgo: 3_600)
        let fresh = scratch.rollout("t3-fresh", lines: [CodexScratch.line("task_started")])

        let provider = provider()
        try await provider.start()
        #expect(await provider.watched[CodexRollout.sessionID(for: old)] == nil)
        let live = await provider.watched[CodexRollout.sessionID(for: fresh)]
        #expect(live?.reported == .working)
        #expect(live?.turnOpen == true)
        await provider.stop()
    }

    @Test("A working session ends when no codex process remains")
    func deadProcessSweep() async throws {
        let url = scratch.rollout("t6-dead", lines: [CodexScratch.line("task_started")])
        let empty = CodexProvider(
            configuration: scratch.configuration, access: DirectFileAccess(),
            roster: { [] })
        try await empty.start()
        await empty.ingest(url, now: Date())
        let id = CodexRollout.sessionID(for: url)
        #expect(await empty.watched[id]?.reported == .working)
        await empty.sweepForDeadProcess(now: Date())
        #expect(await empty.watched[id] == nil)
        await empty.stop()

        // An unreadable table is "ask again later", never "everything died".
        let blind = CodexProvider(
            configuration: scratch.configuration, access: DirectFileAccess(),
            roster: { nil })
        try await blind.start()
        let url2 = scratch.rollout("t7-blind", lines: [CodexScratch.line("task_started")])
        await blind.ingest(url2, now: Date())
        await blind.sweepForDeadProcess(now: Date())
        #expect(await blind.watched[CodexRollout.sessionID(for: url2)] != nil)
        await blind.stop()
    }

    @Test("Silence idles a closed turn but ends an open one only past the grace")
    func idleSweep() async throws {
        let url = scratch.rollout("t4-grace", lines: [CodexScratch.line("task_started")])
        let provider = provider()
        try await provider.start()
        let now = Date()
        await provider.ingest(url, now: now)
        let id = CodexRollout.sessionID(for: url)

        // Inside the grace: silence keeps the heartbeat, the session survives.
        await provider.sweepForIdle(now: now.addingTimeInterval(120))
        #expect(await provider.watched[id]?.reported == .working)

        // Past the grace with the answer still owed: the session ends as a
        // stall rather than idling as a finished turn.
        await provider.sweepForIdle(now: now.addingTimeInterval(16 * 60))
        #expect(await provider.watched[id] == nil)

        // A closed turn, by contrast, just idles after the short horizon.
        let done = scratch.rollout(
            "t5-done", lines: [CodexScratch.line("task_started"), CodexScratch.line("task_complete")])
        await provider.ingest(done, now: now)
        let doneID = CodexRollout.sessionID(for: done)
        #expect(await provider.watched[doneID]?.reported == .idle)
        await provider.stop()
    }
}
