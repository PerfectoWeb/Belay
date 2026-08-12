import BelaySupport
import Foundation
import Testing

@testable import BelayProviders

@Suite("TranscriptCursor")
struct TranscriptCursorTests {
    private let access = DirectFileAccess()
    private let scratch = TranscriptScratch()

    private func cursor(for url: URL, seed: TranscriptCursor.Seed) -> TranscriptCursor {
        var cursor = TranscriptCursor(url: url)
        if let snapshot = FileSnapshot(url: url) { cursor.seed(seed, snapshot: snapshot) }
        return cursor
    }

    @Test("Seeding at EOF ingests no history and no bytes")
    func seedAtEndOfFile() {
        let url = scratch.transcript(
            "a", lines: [TranscriptScratch.record("assistant", stop: "end_turn")])
        var cursor = self.cursor(for: url, seed: .endOfFile)
        let delta = cursor.read(using: access)
        #expect(delta.lines.isEmpty)
        #expect(delta.bytesRead == 0)
        #expect(delta.indicatesWrite == false)
    }

    @Test("Only the delta is read, and the cursor never rewinds to zero")
    func readsOnlyTheDelta() {
        let seedLine = TranscriptScratch.record("user")
        let url = scratch.transcript("a", lines: Array(repeating: seedLine, count: 20))
        let seededSize = FileSnapshot(url: url)?.size ?? 0
        var cursor = self.cursor(for: url, seed: .endOfFile)
        #expect(cursor.currentOffset == seededSize)

        let appended = TranscriptScratch.record("assistant", stop: "tool_use") + "\n"
        scratch.append(appended, to: url)
        let delta = cursor.read(using: access)
        #expect(delta.lines.count == 1)
        #expect(delta.bytesRead == appended.utf8.count)
        #expect(cursor.currentOffset == seededSize + UInt64(appended.utf8.count))
        // A second read with nothing appended must not re-read anything at all.
        #expect(cursor.read(using: access) == .quiet)
    }

    @Test("A partial trailing line is held back and completed by the next delta")
    func partialTrailingLine() {
        let url = scratch.transcript("a")
        var cursor = self.cursor(for: url, seed: .endOfFile)
        let whole = TranscriptScratch.record("assistant", stop: "end_turn")
        let split = whole.index(whole.startIndex, offsetBy: 20)

        scratch.append(String(whole[..<split]), to: url)
        #expect(cursor.read(using: access).lines.isEmpty)

        scratch.append(String(whole[split...]) + "\n", to: url)
        #expect(cursor.read(using: access).lines == [whole])
    }

    @Test("CRLF transcripts parse without the carriage return")
    func carriageReturns() {
        let lines = Fixture.lines("crlf")
        #expect(lines.count == 3)
        #expect(lines.allSatisfy { !$0.hasSuffix("\r") })
    }

    @Test("An empty transcript is silence, not a failure")
    func emptyFile() {
        guard let url = Fixture.url("empty") else {
            Issue.record("missing fixture")
            return
        }
        var cursor = TranscriptCursor(url: url)
        if let snapshot = FileSnapshot(url: url) { cursor.seed(.tailWindow, snapshot: snapshot) }
        #expect(cursor.read(using: access) == .quiet)
    }

    @Test("A vanished transcript reads as silence rather than crashing")
    func missingFile() {
        let url = scratch.transcript("a", lines: [TranscriptScratch.record("user")])
        var cursor = self.cursor(for: url, seed: .endOfFile)
        try? FileManager.default.removeItem(at: url)
        #expect(cursor.read(using: access) == .quiet)
    }

    @Test("Truncation resets the cursor and resumes from the new file")
    func truncationResyncs() {
        let url = scratch.transcript(
            "a", lines: Array(repeating: TranscriptScratch.record("user"), count: 40))
        var cursor = self.cursor(for: url, seed: .endOfFile)
        #expect(cursor.currentOffset > 0)

        try? Data().write(to: url)
        let survivor = TranscriptScratch.record("assistant", stop: "end_turn")
        scratch.append(survivor + "\n", to: url)

        let delta = cursor.read(using: access)
        #expect(delta.didReset)
        #expect(delta.lines == [survivor])
    }

    @Test("A new inode under the same path forces a re-sync")
    func inodeChangeResyncs() {
        let url = scratch.transcript("a", lines: [TranscriptScratch.record("user")])
        let firstInode = FileSnapshot(url: url)?.inode
        var cursor = self.cursor(for: url, seed: .endOfFile)

        let replacement = scratch.projects.appendingPathComponent("replacement.jsonl")
        let line = TranscriptScratch.record("assistant", stop: "tool_use")
        try? Data((line + "\n").utf8).write(to: replacement)
        _ = try? FileManager.default.replaceItemAt(url, withItemAt: replacement)

        #expect(FileSnapshot(url: url)?.inode != firstInode)
        let delta = cursor.read(using: access)
        #expect(delta.didReset)
        #expect(delta.lines == [line])
    }

    @Test("An oversized delta skips to the tail window instead of replaying history")
    func oversizedDeltaIsCapped() {
        let url = scratch.transcript("a")
        var cursor = self.cursor(for: url, seed: .endOfFile)
        let line = TranscriptScratch.record("assistant", stop: "tool_use") + "\n"
        let repeats = (TranscriptCursor.maxDelta / line.utf8.count) + 400
        scratch.append(String(repeating: line, count: repeats), to: url)

        let delta = cursor.read(using: access)
        #expect(delta.didReset)
        #expect(delta.bytesRead <= TranscriptCursor.resyncWindow)
        #expect(delta.lines.count < repeats)
        #expect(delta.lines.allSatisfy { $0 == String(line.dropLast()) })
    }

    @Test("A multi-megabyte transcript is never read whole")
    func multiMegabyteFile() {
        let url = scratch.transcript("big")
        let line = TranscriptScratch.record("assistant", stop: "tool_use") + "\n"
        let block = String(repeating: line, count: 4_000)
        for _ in 0..<12 { scratch.append(block, to: url) }
        let size = FileSnapshot(url: url)?.size ?? 0
        #expect(size > 5 * 1024 * 1024)

        var cursor = self.cursor(for: url, seed: .endOfFile)
        let tail = TranscriptScratch.record("assistant", stop: "end_turn") + "\n"
        scratch.append(tail, to: url)

        let delta = cursor.read(using: access)
        #expect(delta.bytesRead == tail.utf8.count)
        #expect(delta.didReset == false)
        #expect(delta.lines.count == 1)
    }
}
