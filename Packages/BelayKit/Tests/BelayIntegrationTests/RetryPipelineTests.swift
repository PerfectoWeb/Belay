import BelayCore
import BelayPower
import BelayProviders
import Foundation
import Testing

/// The retry bugs of 2026-08-18, replayed through the whole pipeline: a prompt
/// goes out, the API never answers, and the transcript is silent for longer
/// than every window that used to matter. docs/DISCOVERY §2.3.
///
/// Scaled so the interesting arithmetic still holds: the heartbeat cadence
/// (one tick) stays under the session TTL, the TTL stays under the awaiting
/// grace, and the silence asserted on exceeds both the idle horizon and the
/// TTL — which is exactly the combination that used to read as Idle.
@Suite(.serialized)
struct RetryPipelineTests {
    private var harness: PipelineHarness {
        var harness = PipelineHarness()
        harness.idleAfter = 1.0
        harness.grace = 1.0
        harness.sessionTTL = 2.0
        harness.awaitingAssistantGrace = 5.0
        harness.tickInterval = 0.5
        return harness
    }

    @Test("A retry loop's silence keeps the hold, and the grace still bounds it")
    func retrySilenceKeepsHolding() async throws {
        let harness = self.harness
        let space = try harness.makeWorkspace()
        let pipe = await harness.makePipeline(projects: space.projects, sessions: space.sessions)
        try await pipe.provider.start()
        defer { Task { await pipe.shutdown() } }

        try harness.append(PipelineHarness.userPrompt, to: space.transcript)
        #expect(await harness.waitFor("a hold") { await pipe.assertions.isHeld })

        // Three seconds of nothing: triple the idle horizon, past the TTL. This
        // is the "Model overloaded · retrying" window, and it must stay held.
        try await Task.sleep(nanoseconds: 3_000_000_000)
        #expect(await pipe.assertions.isHeld, "retry silence dropped the hold")
        #expect(await pipe.coordinator.snapshot.state == .working)

        // The CLI gives up one attempt; the error record must read as a turn
        // still owed an answer, not as a finish.
        try harness.append(PipelineHarness.apiError, to: space.transcript)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        #expect(await pipe.assertions.isHeld, "the API-error record finished the turn")

        // Past the grace with no further sign of the CLI: release, because from
        // here Belay would be guessing, not observing.
        #expect(
            await harness.waitFor("the bounded release", timeout: 12) {
                await pipe.assertions.isHeld == false
            })
    }

    @Test("The answer arriving after retries ends the turn normally")
    func answerAfterRetriesReleases() async throws {
        let harness = self.harness
        let space = try harness.makeWorkspace()
        let pipe = await harness.makePipeline(projects: space.projects, sessions: space.sessions)
        try await pipe.provider.start()
        defer { Task { await pipe.shutdown() } }

        try harness.append(PipelineHarness.userPrompt, to: space.transcript)
        #expect(await harness.waitFor("a hold") { await pipe.assertions.isHeld })
        try await Task.sleep(nanoseconds: 2_000_000_000)

        try harness.append(PipelineHarness.finished, to: space.transcript)
        #expect(
            await harness.waitFor("a release", timeout: 8) {
                await pipe.assertions.isHeld == false
            })

        let creates = await pipe.backend.createCount
        let releases = await pipe.backend.releaseCount
        #expect(creates == releases, "create/release unbalanced: \(creates) vs \(releases)")
    }
}
