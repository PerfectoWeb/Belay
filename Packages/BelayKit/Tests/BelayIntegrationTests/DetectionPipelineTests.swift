import BelayCore
import BelayPower
import BelayProviders
import Foundation
import Testing

/// The whole pipeline, end to end: a real transcript file on disk →
/// `ClaudeCodeProvider` → `SignalBus` → `ActivityCoordinator` →
/// `PowerAssertionController` on a mock backend, asserting on the resulting
/// hold/release timeline (docs/08 §3).
///
/// Runs against real time and real FSEvents rather than a `TestClock`, because
/// what is being tested here is exactly the machinery a fake clock replaces.
/// Intervals are scaled down so the suite stays a few seconds.
@Suite(.serialized)
struct DetectionPipelineTests {
    private static let idleAfter: TimeInterval = 1.5
    private static let grace: TimeInterval = 1.5

    struct Pipeline {
        let provider: ClaudeCodeProvider
        let coordinator: ActivityCoordinator
        let backend: MockPowerAssertionBackend
        let assertions: PowerAssertionController
        let driver: CoordinatorDriver
        /// Held only so it stays alive. `SignalBus.deinit` cancels its pumps and
        /// finishes its continuations, so letting it fall out of scope silently
        /// severs provider → coordinator. `BelayController` retains it as a
        /// stored property for the same reason.
        let bus: SignalBus

        func shutdown() async {
            await provider.stop()
            await driver.stop()
        }
    }

    private func makePipeline(projects: URL, sessions: URL) async -> Pipeline {
        var policy = AwakePolicy.default
        policy.gracePeriod = Self.grace
        policy.sessionTTL = 600
        policy.assertionTimeout = 60

        let provider = ClaudeCodeProvider(
            configuration: .init(
                projectsDirectory: projects,
                sessionsDirectory: sessions,
                inferredIdleAfter: Self.idleAfter,
                staleAtStartupAfter: 600,
                latency: 0.2
            )
        )
        let coordinator = ActivityCoordinator(policy: policy)
        let backend = MockPowerAssertionBackend()
        let controller = PowerAssertionController(backend: backend)
        let bus = SignalBus()

        // The coordinator is deliberately reactive: with no driver, nothing
        // re-evaluates once the last signal has landed and a cooling-down hold
        // would never expire. The real app starts one in BelayController.
        let driver = CoordinatorDriver(coordinator: coordinator)
        await driver.start()

        await bus.attach(provider.signals)
        let stream = await bus.subscribe()
        Task {
            for await signal in stream {
                await coordinator.ingest(signal)
                await driver.nudge()
            }
        }
        let decisions = await coordinator.decisions()
        Task {
            for await decision in decisions {
                switch decision {
                case .hold(let reason, _):
                    await controller.hold(reason: reason, includeDisplay: false, timeout: 60)
                case .release:
                    await controller.release()
                }
            }
        }
        return Pipeline(
            provider: provider,
            coordinator: coordinator,
            backend: backend,
            assertions: controller,
            driver: driver,
            bus: bus
        )
    }

    struct Workspace {
        let projects: URL
        let sessions: URL
        let transcript: URL
    }

    private func makeWorkspace() throws -> Workspace {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("belay-pipeline-\(UUID().uuidString)", isDirectory: true)
        let project = root.appendingPathComponent("projects/-tmp-acme-api", isDirectory: true)
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        return Workspace(
            projects: root.appendingPathComponent("projects", isDirectory: true),
            sessions: sessions,
            transcript: project.appendingPathComponent("\(UUID().uuidString).jsonl")
        )
    }

    private func append(_ record: String, to url: URL) throws {
        let line = Data((record + "\n").utf8)
        guard let handle = try? FileHandle(forWritingTo: url) else {
            return try line.write(to: url)
        }
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    private let working =
        #"{"type":"assistant","message":{"role":"assistant","stop_reason":"tool_use","content":[]}}"#
    private let finished =
        #"{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn","content":[]}}"#
    /// What a real transcript actually ends with in 12 of 13 sessions
    /// (docs/DISCOVERY §2.1). The turn must still read as over.
    private let metadataTail =
        #"{"type":"last-prompt","lastPrompt":"x","leafUuid":"u","sessionId":"s"}"#

    /// Polls rather than sleeping a fixed span: FSEvents latency is not a number
    /// we control precisely, and a fixed sleep is flaky in both directions.
    @discardableResult
    private func waitFor(
        _ what: String,
        timeout: TimeInterval = 8,
        _ condition: () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        Issue.record("timed out waiting for \(what)")
        return false
    }

    @Test("A growing transcript holds, and silence releases after idle plus grace")
    func holdsThenReleases() async throws {
        let space = try makeWorkspace()
        let pipe = await makePipeline(projects: space.projects, sessions: space.sessions)
        try await pipe.provider.start()
        defer { Task { await pipe.shutdown() } }

        try append(working, to: space.transcript)
        #expect(await waitFor("a hold") { await pipe.assertions.isHeld })
        #expect(await pipe.coordinator.snapshot.state == .working)

        #expect(await waitFor("a release", timeout: 12) { await pipe.assertions.isHeld == false })

        let creates = await pipe.backend.createCount
        let releases = await pipe.backend.releaseCount
        #expect(creates == releases, "create/release unbalanced: \(creates) vs \(releases)")
        #expect(creates >= 1)
    }

    @Test("A turn ending on a metadata record still reads as finished")
    func metadataTailEndsTheTurn() async throws {
        let space = try makeWorkspace()
        let pipe = await makePipeline(projects: space.projects, sessions: space.sessions)
        try await pipe.provider.start()
        defer { Task { await pipe.shutdown() } }

        try append(working, to: space.transcript)
        #expect(await waitFor("a hold") { await pipe.assertions.isHeld })

        try append(finished, to: space.transcript)
        try append(metadataTail, to: space.transcript)

        #expect(await waitFor("a release", timeout: 12) { await pipe.assertions.isHeld == false })
    }

    @Test("Work resuming inside the grace period never drops the assertion")
    func continuousWorkKeepsHolding() async throws {
        let space = try makeWorkspace()
        let pipe = await makePipeline(projects: space.projects, sessions: space.sessions)
        try await pipe.provider.start()
        defer { Task { await pipe.shutdown() } }

        try append(working, to: space.transcript)
        #expect(await waitFor("a hold") { await pipe.assertions.isHeld })

        for _ in 0..<4 {
            try await Task.sleep(nanoseconds: 700_000_000)
            try append(working, to: space.transcript)
            #expect(await pipe.assertions.isHeld, "a pause shorter than grace dropped the hold")
        }

        // One assertion for the whole run, not one per burst of writes.
        #expect(await pipe.backend.createCount == 1, "the assertion was churned instead of held")
    }

    @Test("Transcripts already on disk at startup are not mistaken for live work")
    func staleTranscriptsIgnoredAtStartup() async throws {
        let space = try makeWorkspace()
        try append(working, to: space.transcript)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-3600)],
            ofItemAtPath: space.transcript.path
        )
        // Editing the mtime is itself a filesystem event. Let it drain before the
        // watcher starts, or the test measures its own setup.
        try await Task.sleep(nanoseconds: 1_500_000_000)

        let pipe = await makePipeline(projects: space.projects, sessions: space.sessions)
        try await pipe.provider.start()
        defer { Task { await pipe.shutdown() } }

        try await Task.sleep(nanoseconds: 2_000_000_000)
        #expect(await pipe.assertions.isHeld == false, "an old transcript pinned the Mac awake at launch")
        #expect(await pipe.backend.createCount == 0)
    }
}
