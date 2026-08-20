import BelayCore
import BelayPower
import BelayProviders
import Foundation
import Testing

/// The everyday timelines through the whole pipeline. The harness and the
/// reasons it runs on real time live in `PipelineHarness`.
@Suite(.serialized)
struct DetectionPipelineTests {
    private let harness = PipelineHarness()

    @Test("A growing transcript holds, and silence releases after idle plus grace")
    func holdsThenReleases() async throws {
        let space = try harness.makeWorkspace()
        let pipe = await harness.makePipeline(projects: space.projects, sessions: space.sessions)
        try await pipe.provider.start()
        defer { Task { await pipe.shutdown() } }

        try harness.append(PipelineHarness.working, to: space.transcript)
        #expect(await harness.waitFor("a hold") { await pipe.assertions.isHeld })
        #expect(await pipe.coordinator.snapshot.state == .working)

        #expect(
            await harness.waitFor("a release", timeout: 12) {
                await pipe.assertions.isHeld == false
            })

        let creates = await pipe.backend.createCount
        let releases = await pipe.backend.releaseCount
        #expect(creates == releases, "create/release unbalanced: \(creates) vs \(releases)")
        #expect(creates >= 1)
    }

    @Test("A turn ending on a metadata record still reads as finished")
    func metadataTailEndsTheTurn() async throws {
        let space = try harness.makeWorkspace()
        let pipe = await harness.makePipeline(projects: space.projects, sessions: space.sessions)
        try await pipe.provider.start()
        defer { Task { await pipe.shutdown() } }

        try harness.append(PipelineHarness.working, to: space.transcript)
        #expect(await harness.waitFor("a hold") { await pipe.assertions.isHeld })

        try harness.append(PipelineHarness.finished, to: space.transcript)
        try harness.append(PipelineHarness.metadataTail, to: space.transcript)

        #expect(
            await harness.waitFor("a release", timeout: 12) {
                await pipe.assertions.isHeld == false
            })
    }

    @Test("Work resuming inside the grace period never drops the assertion")
    func continuousWorkKeepsHolding() async throws {
        let space = try harness.makeWorkspace()
        let pipe = await harness.makePipeline(projects: space.projects, sessions: space.sessions)
        try await pipe.provider.start()
        defer { Task { await pipe.shutdown() } }

        try harness.append(PipelineHarness.working, to: space.transcript)
        #expect(await harness.waitFor("a hold") { await pipe.assertions.isHeld })

        for _ in 0..<4 {
            try await Task.sleep(nanoseconds: 700_000_000)
            try harness.append(PipelineHarness.working, to: space.transcript)
            #expect(await pipe.assertions.isHeld, "a pause shorter than grace dropped the hold")
        }

        // One hold for the whole run, not one per burst of writes. Two
        // creates, because a hold is a pair now: sleep plus its network
        // companion.
        #expect(await pipe.backend.createCount == 2, "the assertion was churned instead of held")
    }

    @Test("Transcripts already on disk at startup are not mistaken for live work")
    func staleTranscriptsIgnoredAtStartup() async throws {
        let space = try harness.makeWorkspace()
        try harness.append(PipelineHarness.working, to: space.transcript)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-3600)],
            ofItemAtPath: space.transcript.path
        )
        // Editing the mtime is itself a filesystem event. Let it drain before the
        // watcher starts, or the test measures its own setup.
        try await Task.sleep(nanoseconds: 1_500_000_000)

        let pipe = await harness.makePipeline(projects: space.projects, sessions: space.sessions)
        try await pipe.provider.start()
        defer { Task { await pipe.shutdown() } }

        try await Task.sleep(nanoseconds: 2_000_000_000)
        #expect(
            await pipe.assertions.isHeld == false,
            "an old transcript pinned the Mac awake at launch")
        #expect(await pipe.backend.createCount == 0)
    }
}
