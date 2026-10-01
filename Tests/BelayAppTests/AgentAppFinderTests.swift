import BelayCore
import BelaySupport
import XCTest

@testable import Belay

/// Which app a click on a banner brings forward. The process table and the
/// running apps are dictionaries here; the only real thing is a folder of
/// sidecar files, like `~/.claude/sessions`.
@MainActor
final class AgentAppFinderTests: XCTestCase {
    private var folder = URL(fileURLWithPath: "/")

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("belay-finder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func sidecar(session: String, entrypoint: String?) throws {
        // This process, so that it is alive without starting another.
        let pid = getpid()
        let entry = entrypoint.map { #","entrypoint":"\#($0)""# } ?? ""
        let json = #"{"pid":\#(pid),"sessionId":"\#(session)","cwd":"/w/Belay"\#(entry)}"#
        try Data(json.utf8).write(to: folder.appendingPathComponent("\(pid).json"))
    }

    private func finder(
        ancestry: FakeAncestry = FakeAncestry(), running: Set<String> = []
    ) -> AgentAppFinder {
        let folder = folder
        return AgentAppFinder(
            sessionFolders: { [folder] }, access: DirectFileAccess(), ancestry: ancestry,
            isRunning: { running.contains($0) })
    }

    func testAClaudeDesktopSessionRaisesTheClaudeApp() throws {
        try sidecar(session: "s", entrypoint: "claude-desktop")
        XCTAssertEqual(
            finder().bundleID(provider: .claudeCode, session: SessionID("s")),
            "com.anthropic.claudefordesktop")
    }

    func testATerminalSessionRaisesWhoeverOwnsTheProcess() throws {
        try sidecar(session: "s", entrypoint: "cli")
        let ancestry = FakeAncestry(
            apps: [100: "com.apple.Terminal"], parents: [getpid(): 300, 300: 200, 200: 100])
        XCTAssertEqual(
            finder(ancestry: ancestry).bundleID(provider: .claudeCode, session: SessionID("s")),
            "com.apple.Terminal")
    }

    func testASessionWithoutASidecarRaisesNothing() throws {
        try sidecar(session: "s", entrypoint: "claude-desktop")
        XCTAssertNil(finder().bundleID(provider: .claudeCode, session: SessionID("other")))
    }

    func testCodexRaisesChatGPTOnlyWhileItRuns() {
        XCTAssertEqual(
            finder(running: ["com.openai.codex"]).bundleID(provider: .codex, session: SessionID("c")),
            "com.openai.codex")
        XCTAssertNil(finder().bundleID(provider: .codex, session: SessionID("c")))
    }

    func testOtherAgentsRaiseNothing() {
        XCTAssertNil(finder(running: ["com.openai.codex"]).bundleID(provider: .cline, session: SessionID("c")))
    }

    func testTheWalkStopsAtTheFirstAppAndAtTheTop() {
        let apps: [pid_t: String] = [10: "com.example.first", 5: "com.example.second"]
        let parents: [pid_t: pid_t] = [40: 30, 30: 20, 20: 10, 10: 5, 5: 1]
        XCTAssertEqual(
            ProcessWalk.owner(of: 40, parent: { parents[$0] }, app: { apps[$0] }),
            "com.example.first")
        XCTAssertNil(ProcessWalk.owner(of: 40, parent: { parents[$0] }, app: { _ in nil }))
        XCTAssertNil(ProcessWalk.owner(of: 1, parent: { parents[$0] }, app: { _ in "x" }))
    }

    func testTheWalkEndsOnACycle() {
        let parents: [pid_t: pid_t] = [10: 20, 20: 30, 30: 10]
        XCTAssertNil(ProcessWalk.owner(of: 10, parent: { parents[$0] }, app: { _ in nil }))
    }
}
