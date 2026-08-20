import BelayCore
import BelaySupport
import Foundation
import Testing

@testable import BelayProviders

/// The records Claude Code writes after a turn closes — titles, summaries —
/// are bytes, and bytes used to be work. In its own file because the provider
/// suite is at the linter's length limit.
@Suite("Post-turn bookkeeping")
struct ClaudeCodeBookkeepingTests {
    private let scratch = TranscriptScratch()

    @Test("Post-turn bookkeeping never resurrects an idle session")
    func metadataNeverResurrects() async throws {
        let url = scratch.transcript(
            "bookkeeping", lines: [TranscriptScratch.record("assistant", stop: "end_turn")])
        let provider = ClaudeCodeProvider(
            configuration: scratch.configuration, access: DirectFileAccess())
        try await provider.start()
        await provider.ingest(url, now: Date())
        let id = TranscriptWatch.sessionID(for: url)
        #expect(await provider.watched[id]?.reported == .idle)

        // The title and summary records Claude Code writes after a turn: bytes,
        // but not a beginning.
        scratch.append(TranscriptScratch.record("summary") + "\n", to: url)
        await provider.ingest(url, now: Date())
        #expect(await provider.watched[id]?.reported == .idle)

        // A real prompt still opens the turn.
        scratch.append(TranscriptScratch.record("user") + "\n", to: url)
        await provider.ingest(url, now: Date())
        #expect(await provider.watched[id]?.reported == .working)
        await provider.stop()
    }
}
