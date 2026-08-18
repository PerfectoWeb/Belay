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
/// Intervals are scaled down so the suites stay a few seconds.
struct PipelineHarness {
    var idleAfter: TimeInterval = 1.5
    var grace: TimeInterval = 1.5
    var sessionTTL: TimeInterval = 600
    var awaitingAssistantGrace: TimeInterval = 900
    var tickInterval: TimeInterval = 5

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

    struct Workspace {
        let projects: URL
        let sessions: URL
        let transcript: URL
    }

    func makePipeline(projects: URL, sessions: URL) async -> Pipeline {
        var policy = AwakePolicy.default
        policy.gracePeriod = grace
        policy.sessionTTL = sessionTTL
        policy.assertionTimeout = 60

        let provider = ClaudeCodeProvider(
            configuration: .init(
                projectsDirectory: projects,
                sessionsDirectory: sessions,
                inferredIdleAfter: idleAfter,
                awaitingAssistantGrace: awaitingAssistantGrace,
                staleAtStartupAfter: 600,
                latency: 0.2,
                tickInterval: tickInterval
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

    func makeWorkspace() throws -> Workspace {
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

    func append(_ record: String, to url: URL) throws {
        let line = Data((record + "\n").utf8)
        guard let handle = try? FileHandle(forWritingTo: url) else {
            return try line.write(to: url)
        }
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    /// Polls rather than sleeping a fixed span: FSEvents latency is not a number
    /// we control precisely, and a fixed sleep is flaky in both directions.
    @discardableResult
    func waitFor(
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

    static let working =
        #"{"type":"assistant","message":{"role":"assistant","stop_reason":"tool_use","content":[]}}"#
    static let finished =
        #"{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn","content":[]}}"#
    /// What a real transcript actually ends with in 12 of 13 sessions
    /// (docs/DISCOVERY §2.1). The turn must still read as over.
    static let metadataTail =
        #"{"type":"last-prompt","lastPrompt":"x","leafUuid":"u","sessionId":"s"}"#
    /// A prompt on its way to the API: the model owes the next record
    /// (docs/DISCOVERY §2.3).
    static let userPrompt =
        #"{"type":"user","message":{"role":"user","content":[]}}"#
    /// The CLI giving up one retry attempt, shaped like the real record.
    static let apiError =
        #"{"type":"assistant","error":"server_error","apiErrorStatus":529,"#
        + #""isApiErrorMessage":true,"message":{"role":"assistant","#
        + #""stop_reason":"stop_sequence","content":[]}}"#
}
