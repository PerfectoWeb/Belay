import BelayCore
import BelaySupport
import XCTest

@testable import BelayProviders

/// Attributing a subagent to the session that spawned it, from its path alone.
///
/// The bug these exist to prevent was visible in the menu bar: fifty-four
/// workflow agents under `wf_60f0c106-9d2` each took a top-level row named
/// "9d2", which is the tail of the *workflow* folder, and pushed the real
/// session out of a five-row panel.
final class SubagentTranscriptTests: XCTestCase {
    private let scratch = TranscriptScratch()

    func testAPlainSessionHasNoParent() {
        let url = scratch.transcript("s1", project: "-Volumes-Work-f64")
        let location = TranscriptLocation(transcript: url)
        XCTAssertNil(location.parent)
        XCTAssertFalse(location.isSubagent)
        XCTAssertEqual(TranscriptWatch.workspaceName(for: url), "f64")
    }

    func testTaskSubagentPointsAtItsSession() {
        let url = scratch.subagent("agent-a1", of: "s1", project: "-Volumes-Work-f64")
        XCTAssertEqual(TranscriptLocation(transcript: url).parent, SessionID("s1"))
    }

    func testWorkflowSubagentPointsAtTheSessionNotTheWorkflow() {
        let url = scratch.subagent(
            "agent-a1", of: "s1", project: "-Volumes-Work-f64", workflow: "wf_60f0c106-9d2")
        XCTAssertEqual(TranscriptLocation(transcript: url).parent, SessionID("s1"))
    }

    /// The regression itself: a subagent belongs to the project its session is
    /// in, never to the folder it happens to sit in.
    func testSubagentsInheritTheProjectName() {
        let task = scratch.subagent("agent-a1", of: "s1", project: "-Volumes-Work-f64")
        let workflow = scratch.subagent(
            "agent-a2", of: "s1", project: "-Volumes-Work-f64", workflow: "wf_60f0c106-9d2")
        XCTAssertEqual(TranscriptWatch.workspaceName(for: task), "f64")
        XCTAssertEqual(TranscriptWatch.workspaceName(for: workflow), "f64")
    }

    func testSeedingFindsSubagentsAsWellAsSessions() {
        scratch.transcript("s1", project: "-Volumes-Work-f64")
        scratch.subagent("agent-a1", of: "s1", project: "-Volumes-Work-f64")
        scratch.subagent("agent-a2", of: "s1", project: "-Volumes-Work-f64", workflow: "wf_1")

        let found = TranscriptWatch.transcripts(under: scratch.projects, access: DirectFileAccess())
        XCTAssertEqual(
            Set(found.map { TranscriptWatch.sessionID(for: $0).rawValue }),
            ["s1", "agent-a1", "agent-a2"])
    }

    /// The sidecar is read for `agentType` and nothing else. `description` is a
    /// summary of the user's prompt and the About pane promises those are never
    /// touched, so it must not reach the UI.
    func testOnlyTheAgentTypeIsReadFromTheSidecar() {
        let url = scratch.subagent("agent-a1", of: "s1", kind: "general-purpose")
        XCTAssertEqual(TranscriptLocation.kind(of: url, access: DirectFileAccess()), "general-purpose")
    }

    func testAMissingSidecarIsNotAnError() {
        let url = scratch.subagent("agent-a1", of: "s1")
        XCTAssertNil(TranscriptLocation.kind(of: url, access: DirectFileAccess()))
    }

    /// The workflow runner's own bookkeeping file grows for the whole run, and
    /// sits right beside the agents. Followed, it becomes a session row called
    /// "journal" that the user never started.
    func testTheWorkflowJournalIsNotASession() async throws {
        let journal = scratch.subagent("journal", of: "s1", workflow: "wf_1")
        let provider = ClaudeCodeProvider(configuration: scratch.configuration)
        let collector = SignalCollector()
        await collector.attach(to: provider.signals)
        try await provider.start()
        defer { Task { await provider.stop() } }

        await provider.ingest(journal, now: Date())
        let signals = await collector.settle()

        XCTAssertTrue(signals.isEmpty, "the workflow journal was adopted as a session")
        await collector.stop()
    }

    /// End to end: the signal a subagent produces has to carry the parent, or
    /// the panel has nothing to group by.
    func testProviderReportsTheParentOnSubagentSignals() async throws {
        let url = scratch.subagent(
            "agent-a1", of: "s1", project: "-Volumes-Work-f64", workflow: "wf_1", kind: "explorer")
        let provider = ClaudeCodeProvider(configuration: scratch.configuration)
        let collector = SignalCollector()
        await collector.attach(to: provider.signals)
        try await provider.start()
        defer { Task { await provider.stop() } }

        await provider.ingest(url, now: Date())
        let signals = await collector.wait(for: 1)

        let signal = try XCTUnwrap(signals.first)
        XCTAssertEqual(signal.session, SessionID("agent-a1"))
        XCTAssertEqual(signal.parent, SessionID("s1"))
        XCTAssertEqual(signal.kind, "explorer")
        XCTAssertEqual(signal.workspace, "f64")
        await collector.stop()
    }
}
