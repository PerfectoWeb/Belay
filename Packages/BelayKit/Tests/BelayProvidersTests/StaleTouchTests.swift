import BelayCore
import BelaySupport
import Foundation
import Testing

@testable import BelayProviders

/// The stale-touch guard, on both providers: a file whose mtime moves while
/// its record clocks stand still is a toucher's work — Codex Desktop's
/// session importer raised thirty month-old subagents as Working rows in one
/// second (2026-08-24, ws=pdd) — never a turn.
@Suite("Stale-touch guard")
struct StaleTouchTests {
    private let claude = TranscriptScratch()
    private let codex = CodexScratch()

    @Test("A touched old transcript opens nothing at runtime")
    func claudeStaleTouchStaysSilent() async {
        let provider = ClaudeCodeProvider(
            configuration: claude.configuration, access: DirectFileAccess())
        let collector = SignalCollector()
        await collector.attach(to: provider.signals)
        // A fresh mtime over month-old records: an importer's touch, not a
        // turn.
        let url = claude.transcript(
            "touched",
            lines: [
                TranscriptScratch.record(
                    "assistant", stop: "tool_use", at: "2026-07-30T10:00:00.000Z")
            ])
        await provider.ingest(url, now: Date())
        #expect(await collector.settle().isEmpty)
        #expect(await provider.watched[SessionID("touched")] != nil, "the file is still followed")
        #expect(await provider.watched[SessionID("touched")]?.reported == nil)

        // A real append to the same file still announces.
        claude.append(TranscriptScratch.record("assistant", stop: "tool_use") + "\n", to: url)
        await provider.ingest(url, now: Date())
        let signals = await collector.wait(for: 1)
        #expect(signals.map(\.activity) == [.working])
        await collector.stop()
    }

    @Test("An imported rollout with old record clocks opens nothing")
    func codexStaleTouchOpensNothing() async throws {
        let provider = CodexProvider(
            configuration: codex.configuration, access: DirectFileAccess())
        try await provider.start()
        // Appears at runtime with a fresh mtime, but the records are a month
        // old: the importer at work, not a turn.
        let url = codex.rollout(
            "t10-import",
            lines: [
                CodexScratch.meta(cwd: "/tmp/pdd"),
                CodexScratch.line("task_started", at: "2026-07-30T10:00:00.000Z")
            ])
        await provider.ingest(url, now: Date())
        let id = CodexRollout.sessionID(for: url)
        #expect(await provider.watched[id] != nil, "the file is still followed")
        #expect(await provider.watched[id]?.reported == nil, "but nothing was announced")

        // A real turn in the same file still announces.
        let fresh = ISO8601DateFormatter().string(from: Date())
        codex.append([CodexScratch.line("task_started", at: fresh)], to: url)
        await provider.ingest(url, now: Date())
        #expect(await provider.watched[id]?.reported == .working)
        await provider.stop()
    }

    /// The importer's other half: a rollout that appears empty, its content a
    /// heartbeat behind. With no records to read there is no evidence of a
    /// turn, so nothing may be announced — otherwise a file caught between
    /// `creat` and its first write becomes a phantom Working row. This is the
    /// race that failed CI on 2026-08-26 while passing locally.
    @Test("A rollout caught empty announces nothing")
    func codexEmptyRolloutOpensNothing() async throws {
        let provider = CodexProvider(
            configuration: codex.configuration, access: DirectFileAccess())
        try await provider.start()
        let url = codex.rollout("t11-empty", lines: [])
        await provider.ingest(url, now: Date())
        let id = CodexRollout.sessionID(for: url)
        // Not watched yet, on purpose: a watch stored here would route the
        // first bytes around the stale-touch check. They re-enter adopt.
        #expect(await provider.watched[id] == nil)

        // Content arriving a moment later is classified normally.
        let fresh = ISO8601DateFormatter().string(from: Date())
        codex.append([CodexScratch.line("task_started", at: fresh)], to: url)
        await provider.ingest(url, now: Date())
        #expect(await provider.watched[id]?.reported == .working)
        await provider.stop()
    }

    /// The same race on the Claude side: a transcript file that exists but has
    /// not been written to yet.
    @Test("A transcript caught empty announces nothing")
    func claudeEmptyTranscriptOpensNothing() async {
        let provider = ClaudeCodeProvider(
            configuration: claude.configuration, access: DirectFileAccess())
        let collector = SignalCollector()
        await collector.attach(to: provider.signals)
        let url = claude.transcript("empty", lines: [])
        await provider.ingest(url, now: Date())
        #expect(await collector.settle().isEmpty)
        // Not watched yet, on purpose: a watch stored here would route the
        // first bytes around the stale-touch check. They re-enter adopt.
        #expect(await provider.watched[SessionID("empty")] == nil)

        claude.append(TranscriptScratch.record("assistant", stop: "tool_use") + "\n", to: url)
        await provider.ingest(url, now: Date())
        #expect(await collector.wait(for: 1).map(\.activity) == [.working])
        await collector.stop()
    }

    /// The importer race the empty-file guard used to hand a free pass to: a
    /// rollout caught at `creat`, whose first real bytes are a month-old
    /// conversation. They must meet the same stale-touch check any other
    /// appearance does, not slip through an already-stored watch.
    @Test("Stale bytes after an empty first sight open nothing")
    func staleBytesAfterEmptySightOpenNothing() async {
        let provider = CodexProvider(
            configuration: codex.configuration, access: DirectFileAccess())
        let collector = SignalCollector()
        await collector.attach(to: provider.signals)
        let url = codex.rollout("imported", lines: [])
        await provider.ingest(url, now: Date())
        #expect(await collector.settle().isEmpty)

        let monthOld = ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: -30 * 86_400))
        codex.append([CodexScratch.line("task_started", at: monthOld)], to: url)
        await provider.ingest(url, now: Date())
        #expect(await collector.settle().isEmpty, "a month-old conversation is history, not news")
        await collector.stop()
    }
}
