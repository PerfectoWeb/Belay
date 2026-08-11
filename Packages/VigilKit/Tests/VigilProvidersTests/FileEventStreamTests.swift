// Contains one `@unchecked Sendable` type. Justification (docs/07): `EventTally`
// bridges the FSEvents C callback, which lands on a dispatch queue, into a test
// assertion; its only mutable state is an array guarded by an `NSLock`.
import Foundation
import Testing

@testable import VigilProviders

/// Thread-safe tally for the FSEvents callback, which arrives on a dispatch queue.
private final class EventTally: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []

    func record(_ new: [String]) {
        lock.lock()
        defer { lock.unlock() }
        paths.append(contentsOf: new)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return paths.count
    }

    func matches(_ needle: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return paths.contains { $0.hasSuffix(needle) }
    }
}

@Suite("FileEventStream", .serialized)
struct FileEventStreamTests {
    private let queue = DispatchQueue(label: "vigil.tests.fsevents")

    /// Waits on the event we actually care about, never on a count.
    ///
    /// Creating the scratch directory is itself a filesystem event, and FSEvents
    /// delivers it for the watched root about 11 ms after the stream starts even
    /// with `kFSEventStreamEventIdSinceNow`. A `count >= 1` wait is therefore
    /// satisfied before the test has written anything, and the assertion then
    /// races the real event by a few milliseconds — failing on a fast machine and
    /// passing on a slow one, which is the worst kind of test.
    private func waitFor(_ tally: EventTally, file name: String, seconds: TimeInterval = 4) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !tally.matches(name), Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    @Test("FSEvents reports file-level writes under the watched root")
    func deliversFileEvents() async throws {
        let scratch = TranscriptScratch()
        let tally = EventTally()
        let stream = try FileEventStream(root: scratch.projects, latency: 0.1, queue: queue) { paths in
            tally.record(paths)
        }
        defer { stream.stop() }

        // FSEvents needs the stream to be live before the write to report it.
        try await Task.sleep(nanoseconds: 300_000_000)
        let url = scratch.transcript("watched", lines: [TranscriptScratch.record("user")])
        scratch.append(TranscriptScratch.record("assistant", stop: "tool_use") + "\n", to: url)

        await waitFor(tally, file: "watched.jsonl")
        #expect(tally.matches("watched.jsonl"))
        #expect(stream.isRunning)
    }

    @Test("stop() leaves no stream running and no further callbacks")
    func teardownIsComplete() async throws {
        let scratch = TranscriptScratch()
        let tally = EventTally()
        let stream = try FileEventStream(root: scratch.projects, latency: 0.1, queue: queue) { paths in
            tally.record(paths)
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        scratch.transcript("before", lines: [TranscriptScratch.record("user")])
        await waitFor(tally, file: "before.jsonl")

        stream.stop()
        #expect(stream.isRunning == false)
        // Calling stop twice must be harmless: deinit calls it again.
        stream.stop()

        let after = tally.count
        scratch.transcript("after", lines: [TranscriptScratch.record("user")])
        try await Task.sleep(nanoseconds: 700_000_000)
        #expect(tally.count == after)
        #expect(tally.matches("after.jsonl") == false)
    }

    @Test("deinit tears the stream down even when stop() is never called")
    func deinitStopsTheStream() async throws {
        let scratch = TranscriptScratch()
        let tally = EventTally()
        do {
            let stream = try FileEventStream(root: scratch.projects, latency: 0.1, queue: queue) { paths in
                tally.record(paths)
            }
            #expect(stream.isRunning)
            try await Task.sleep(nanoseconds: 300_000_000)
        }

        let after = tally.count
        scratch.transcript("orphan", lines: [TranscriptScratch.record("user")])
        try await Task.sleep(nanoseconds: 700_000_000)
        #expect(tally.count == after)
    }
}
