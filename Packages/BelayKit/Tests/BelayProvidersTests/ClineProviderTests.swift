import BelayCore
import BelaySupport
import Foundation
import Testing

@testable import BelayProviders

/// A `~/.cline/data/sessions` layout on disk, torn down with the suite.
private final class ClineScratch: @unchecked Sendable {
    let root: URL

    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cline-scratch-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    var sessions: URL { root.appendingPathComponent("data/sessions", isDirectory: true) }

    var configuration: ClineProvider.Configuration {
        ClineProvider.Configuration(sessionsDirectory: sessions)
    }

    @discardableResult
    func session(_ id: String, status: String, workspace: String = "/tmp/demo") -> URL {
        let directory = sessions.appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let state = """
            {"version":1,"session_id":"\(id)","status":"\(status)","cwd":"\(workspace)",\
            "workspace_root":"\(workspace)","prompt":"SECRET, never decoded"}
            """
        let url = directory.appendingPathComponent("\(id).json")
        try? Data(state.utf8).write(to: url)
        return url
    }

    func messages(_ id: String, bytes: Int) {
        let url = sessions.appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("\(id).messages.json")
        try? Data(String(repeating: "x", count: bytes).utf8).write(to: url)
    }

    func touch(_ url: URL, secondsAgo: TimeInterval) {
        try? FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-secondsAgo)], ofItemAtPath: url.path)
    }
}

@Suite("ClineProvider")
struct ClineProviderTests {
    private let scratch = ClineScratch()

    private func provider() -> ClineProvider {
        ClineProvider(configuration: scratch.configuration, access: DirectFileAccess())
    }

    @Test("A running session is adopted and ends on its status")
    func runningThenCompleted() async throws {
        let provider = provider()
        try await provider.start()
        scratch.session("s1", status: "running")
        await provider.ingest("s1", now: Date())
        #expect(await provider.watched[SessionID("s1")]?.reported == .working)
        #expect(await provider.watched[SessionID("s1")]?.workspace == "demo")

        scratch.session("s1", status: "completed")
        await provider.ingest("s1", now: Date())
        #expect(await provider.watched[SessionID("s1")] == nil, "completed is gone")
        await provider.stop()
    }

    @Test("An interactive session waiting for its person stays silent at first")
    func idleFirstStaysSilent() async throws {
        let provider = provider()
        try await provider.start()
        scratch.session("s2", status: "idle")
        await provider.ingest("s2", now: Date())
        #expect(await provider.watched[SessionID("s2")]?.reported == .idle)
        #expect(await provider.watched[SessionID("s2")]?.announced == false)

        scratch.session("s2", status: "running")
        await provider.ingest("s2", now: Date())
        #expect(await provider.watched[SessionID("s2")]?.reported == .working)
        #expect(await provider.watched[SessionID("s2")]?.announced == true)
        await provider.stop()
    }

    @Test("A finished session appearing at runtime is history, not news")
    func importedEndedSessionOpensNothing() async throws {
        let provider = provider()
        try await provider.start()
        scratch.session("s3", status: "completed")
        await provider.ingest("s3", now: Date())
        #expect(await provider.watched[SessionID("s3")] == nil)
        await provider.stop()
    }

    @Test("Startup: fresh running announces, old files stay out entirely")
    func startupSeeding() async throws {
        let fresh = scratch.session("live", status: "running")
        _ = fresh
        let stale = scratch.session("old", status: "running")
        scratch.touch(stale, secondsAgo: 3_600)
        let corpse = scratch.session("corpse", status: "running")
        scratch.touch(corpse, secondsAgo: 120)

        let provider = provider()
        try await provider.start()
        #expect(await provider.watched[SessionID("live")]?.reported == .working)
        #expect(await provider.watched[SessionID("old")] == nil, "stale is not followed")
        let followed = await provider.watched[SessionID("corpse")]
        #expect(followed != nil, "merely old is followed")
        #expect(followed?.reported == nil, "but silent until it moves")
        await provider.stop()
    }

    @Test("A quiet running session goes idle: Ctrl-C leaves the status lying")
    func quietSweep() async throws {
        let provider = provider()
        try await provider.start()
        scratch.session("s4", status: "running")
        scratch.messages("s4", bytes: 100)
        let start = Date()
        await provider.ingest("s4", now: start)
        #expect(await provider.watched[SessionID("s4")]?.reported == .working)

        await provider.sweepForIdle(now: start.addingTimeInterval(10))
        #expect(await provider.watched[SessionID("s4")]?.reported == .working)

        // Growth counts as life even though the status never changed.
        scratch.messages("s4", bytes: 500)
        await provider.ingest("s4", now: start.addingTimeInterval(30))
        await provider.sweepForIdle(now: start.addingTimeInterval(50))
        #expect(await provider.watched[SessionID("s4")]?.reported == .working)

        await provider.sweepForIdle(now: start.addingTimeInterval(90))
        #expect(await provider.watched[SessionID("s4")]?.reported == .idle)
        await provider.stop()
    }

    @Test("Availability tells missing installs apart from missing access")
    func availability() async throws {
        #expect(await provider().availability == .ready)

        let absent = ClineProvider.Configuration(
            sessionsDirectory: URL(fileURLWithPath: "/nope-\(UUID().uuidString)/data/sessions"))
        guard case .unavailable = await ClineProvider(configuration: absent).availability else {
            Issue.record("expected unavailable when ~/.cline does not exist")
            return
        }

        let blind = ClineProvider(configuration: scratch.configuration, access: DeniedFileAccess())
        guard case .needsSetup = await blind.availability else {
            Issue.record("expected needsSetup when nothing is readable")
            return
        }
    }

    @Test("Changed paths resolve to their session")
    func pathParsing() {
        let root = scratch.sessions
        #expect(ClineSessions.sessionID(of: root.path + "/abc/abc.json", under: root) == "abc")
        #expect(
            ClineSessions.sessionID(of: root.path + "/abc/abc.messages.json", under: root) == "abc")
        #expect(ClineSessions.sessionID(of: "/somewhere/else.json", under: root) == nil)
    }

    @Test("The state file's prompt is never decoded")
    func promptStaysOut() throws {
        let url = scratch.session("s5", status: "running")
        let state = ClineSessionState.load(from: url, access: DirectFileAccess())
        let mirror = Mirror(reflecting: try #require(state))
        let values = mirror.children.compactMap { $0.value as? String }
        #expect(!values.contains { $0.contains("SECRET") })
    }
}
