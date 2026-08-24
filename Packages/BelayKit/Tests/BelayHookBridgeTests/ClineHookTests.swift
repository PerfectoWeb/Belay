import BelayCore
import Foundation
import Testing

@testable import BelayHookBridge

/// The Cline side of the bridge: payload decoding and the script files.
@Suite("Cline hooks")
struct ClineHookTests {
    private let endpoint = BridgeEndpoint(port: 4242, token: "sekret")

    /// Trimmed from a live capture (2026-08-24); the prompt-shaped fields are
    /// representative of what must never be decoded.
    private let payload = """
        {"clineVersion":"","timestamp":"2026-08-24T12:55:29.277Z","taskId":"conv_1",\
        "sessionContext":{"rootSessionId":"1787576128998_2rh0c"},\
        "workspaceRoots":["/tmp/demo"],"workspaceInfo":{"rootPath":"/tmp/demo","hint":"demo"},\
        "userId":"davx","agent_id":"agent_1","parent_agent_id":null,"hookName":"agent_start",\
        "taskStart":{"taskMetadata":{"prompt":"SECRET"}}}
        """

    @Test("A posted payload becomes an exact signal for the URL's event")
    func decodes() throws {
        let signal = try #require(
            ClineHookEnvelope.signal(
                path: "/hook?src=belay&agent=cline&event=TaskStart",
                body: Data(payload.utf8), at: Date()))
        #expect(signal.provider == .cline)
        #expect(signal.session == SessionID("1787576128998_2rh0c"))
        #expect(signal.activity == .working)
        #expect(signal.workspace == "demo")
        #expect(signal.confidence == .exact)
    }

    @Test(
        "Every event maps to its activity",
        arguments: [
            ("TaskStart", SessionActivity.working), ("TaskResume", .working),
            ("TaskCancel", .idle), ("TaskComplete", .idle), ("TaskError", .idle),
            ("SessionShutdown", .ended)
        ])
    func mapping(event: String, activity: SessionActivity) throws {
        let signal = try #require(
            ClineHookEnvelope.signal(
                path: "/hook?src=belay&agent=cline&event=\(event)",
                body: Data(payload.utf8), at: Date()))
        #expect(signal.activity == activity)
    }

    @Test("An unknown event or a sessionless payload is ignored")
    func refusals() {
        #expect(
            ClineHookEnvelope.signal(
                path: "/hook?src=belay&agent=cline&event=SomethingNew",
                body: Data(payload.utf8), at: Date()) == nil)
        #expect(
            ClineHookEnvelope.signal(
                path: "/hook?src=belay&agent=cline&event=TaskStart",
                body: Data("{}".utf8), at: Date()) == nil)
    }

    @Test("Install writes six scripts; uninstall removes exactly them")
    func roundTrip() throws {
        let scratch = try BridgeScratch()
        let installer = ClineHookInstaller(paths: scratch.paths)
        #expect(!installer.isInstalled())
        try installer.install(endpoint: endpoint)
        #expect(installer.isInstalled())

        let files = try FileManager.default.contentsOfDirectory(atPath: scratch.paths.clineHooks.path)
        #expect(Set(files) == Set(ClineHookEvent.allCases.map { "\($0.rawValue).sh" }))
        let start = try String(
            contentsOf: scratch.paths.clineHooks.appendingPathComponent("TaskStart.sh"),
            encoding: .utf8)
        #expect(start.contains("Bearer sekret"))
        #expect(start.contains("event=TaskStart"))
        #expect(ClineHookConfiguration.isBelayScript(start))

        installer.uninstall()
        #expect(!installer.isInstalled())
        let left = try FileManager.default.contentsOfDirectory(atPath: scratch.paths.clineHooks.path)
        #expect(left.isEmpty)
    }

    @Test("A foreign script under a wanted name is skipped and survives")
    func foreignScriptSurvives() throws {
        let scratch = try BridgeScratch()
        try FileManager.default.createDirectory(
            at: scratch.paths.clineHooks, withIntermediateDirectories: true)
        let theirs = scratch.paths.clineHooks.appendingPathComponent("TaskStart.sh")
        try Data("#!/bin/sh\necho theirs\n".utf8).write(to: theirs)

        let installer = ClineHookInstaller(paths: scratch.paths)
        #expect(installer.occupied() == ["TaskStart.sh"])
        try installer.install(endpoint: endpoint)
        #expect(try String(contentsOf: theirs, encoding: .utf8).contains("echo theirs"))

        installer.uninstall()
        #expect(FileManager.default.fileExists(atPath: theirs.path), "theirs is not ours to remove")
    }

    @Test("Reconcile rewrites a stale port and leaves a current one alone")
    func reconcile() throws {
        let scratch = try BridgeScratch()
        let installer = ClineHookInstaller(paths: scratch.paths)
        #expect(try installer.reconcile(endpoint: endpoint) == .unchanged)
        try installer.install(endpoint: endpoint)
        #expect(try installer.reconcile(endpoint: endpoint) == .unchanged)
        let moved = BridgeEndpoint(port: 5555, token: "sekret")
        #expect(try installer.reconcile(endpoint: moved) == .written)
        let start = try String(
            contentsOf: scratch.paths.clineHooks.appendingPathComponent("TaskStart.sh"),
            encoding: .utf8)
        #expect(start.contains(":5555/"))
    }
}
