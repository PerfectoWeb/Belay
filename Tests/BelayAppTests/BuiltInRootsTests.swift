import BelayCore
import BelayProviders
import XCTest

@testable import Belay

/// The extra watched folders behind issue #4: a `CLAUDE_CONFIG_DIR` profile the
/// user points Belay at by hand, hosted as one more provider instance.
@MainActor
final class BuiltInRootsTests: XCTestCase {
    private var home: URL!
    private var alt: URL!

    override func setUp() async throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("belay-roots-\(UUID().uuidString)", isDirectory: true)
        alt = home.appendingPathComponent("elsewhere/claude-work", isDirectory: true)
        for sub in [".claude/projects", "elsewhere/claude-work/projects"] {
            try FileManager.default.createDirectory(
                at: home.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        UserDefaults.standard.removeObject(forKey: "builtInExtraRoots")
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "builtInExtraRoots")
        try? FileManager.default.removeItem(at: home)
    }

    private func makeHost() -> ProviderHost {
        ProviderHost(
            precise: PreciseDetection(),
            enabled: [.claudeCode],
            home: home)
    }

    func testAddRootHostsRefusesOverlapsAndRemoves() async {
        let host = makeHost()
        _ = await host.start()

        let added = await host.addRoot(alt, for: .claudeCode)
        XCTAssertEqual(added, .added)
        // The same folder again, and a folder inside a watched one: refused.
        let again = await host.addRoot(alt, for: .claudeCode)
        let nested = await host.addRoot(alt.appendingPathComponent("projects"), for: .claudeCode)
        let inDefault = await host.addRoot(home.appendingPathComponent(".claude"), for: .claudeCode)
        XCTAssertEqual(again, .overlaps)
        XCTAssertEqual(nested, .overlaps)
        XCTAssertEqual(inDefault, .overlaps)

        let status = await host.statuses().first { $0.id == .claudeCode }
        XCTAssertEqual(status?.customRoots, [alt.standardizedFileURL.path])

        await host.removeRoot(path: alt.standardizedFileURL.path, for: .claudeCode)
        let after = await host.statuses().first { $0.id == .claudeCode }
        XCTAssertEqual(after?.customRoots, [])
        await host.stop()
    }

    func testStoredRootsAreAdoptedAtStartAndDetect() async throws {
        // Persisted before launch, the way a relaunch finds them.
        BuiltInRootsStore().add(alt, for: .claudeCode)
        let host = makeHost()
        let signals = await host.start()
        try await Task.sleep(nanoseconds: 400_000_000)

        // A fresh turn lands in the custom root only.
        let stamp = ISO8601DateFormatter().string(from: Date())
        let record =
            "{\"type\":\"assistant\",\"sessionId\":\"s\",\"timestamp\":\"\(stamp)\","
            + "\"message\":{\"stop_reason\":\"tool_use\",\"role\":\"assistant\",\"content\":[]}}\n"
        let transcript = alt.appendingPathComponent("projects/-tmp-demo", isDirectory: true)
        try FileManager.default.createDirectory(at: transcript, withIntermediateDirectories: true)
        try Data(record.utf8).write(to: transcript.appendingPathComponent("abc123.jsonl"))

        let seen = expectation(description: "signal from the custom root")
        let pump = Task {
            for await signal in signals where signal.provider == .claudeCode {
                if signal.activity == .working { seen.fulfill() }
                break
            }
        }
        await fulfillment(of: [seen], timeout: 8)
        pump.cancel()
        await host.stop()
    }

    /// The same relaunch path for Cline, whose layout nests one level deeper
    /// (`data/sessions`): a session written into the custom root must reach
    /// the bus. Caught live: the demo root detected for every agent but Cline.
    func testStoredClineRootIsAdoptedAtStartAndDetects() async throws {
        let clineRoot = home.appendingPathComponent("elsewhere/cline-work", isDirectory: true)
        try FileManager.default.createDirectory(
            at: clineRoot.appendingPathComponent("data/sessions"), withIntermediateDirectories: true)
        BuiltInRootsStore().add(clineRoot, for: .cline)
        let host = ProviderHost(
            precise: PreciseDetection(),
            enabled: [.cline],
            home: home)
        let signals = await host.start()
        try await Task.sleep(nanoseconds: 400_000_000)

        let session = clineRoot.appendingPathComponent("data/sessions/demo-1", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let state = """
            {"version":1,"session_id":"demo-1","status":"running",\
            "cwd":"/tmp/demo","workspace_root":"/tmp/demo","prompt":""}
            """
        try Data(state.utf8).write(to: session.appendingPathComponent("demo-1.json"))
        try Data("xxxxxxxxxx".utf8).write(
            to: session.appendingPathComponent("demo-1.messages.json"))

        let seen = expectation(description: "signal from the custom Cline root")
        let pump = Task {
            for await signal in signals where signal.provider == .cline {
                if signal.activity == .working { seen.fulfill() }
                break
            }
        }
        await fulfillment(of: [seen], timeout: 8)
        pump.cancel()
        await host.stop()
    }

    /// The same instance ProviderHost builds, without the host around it.
    func testDirectClineInstanceAtCustomRootDetects() async throws {
        let clineRoot = home.appendingPathComponent("elsewhere/cline-solo", isDirectory: true)
        try FileManager.default.createDirectory(
            at: clineRoot.appendingPathComponent("data/sessions"), withIntermediateDirectories: true)
        let provider = ClineProvider(
            configuration: .at(clineRoot), access: WatchedFolderAccess.provider)
        let signals = await provider.signals
        try await provider.start()
        try await Task.sleep(nanoseconds: 300_000_000)

        let session = clineRoot.appendingPathComponent("data/sessions/demo-2", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let state = """
            {"version":1,"session_id":"demo-2","status":"running",\
            "cwd":"/tmp/demo","workspace_root":"/tmp/demo","prompt":""}
            """
        try Data(state.utf8).write(to: session.appendingPathComponent("demo-2.json"))

        let seen = expectation(description: "direct instance signal")
        let pump = Task {
            for await signal in signals where signal.provider == .cline {
                if signal.activity == .working { seen.fulfill() }
                break
            }
        }
        await fulfillment(of: [seen], timeout: 8)
        pump.cancel()
        await provider.stop()
    }

    func testStoreRoundTripsAndDeduplicates() {
        let store = BuiltInRootsStore()
        store.add(alt, for: .codex)
        store.add(alt, for: .codex)
        XCTAssertEqual(store.roots(for: .codex).map(\.path), [alt.standardizedFileURL.path])
        XCTAssertEqual(store.roots(for: .claudeCode), [])
        store.remove(path: alt.standardizedFileURL.path, for: .codex)
        XCTAssertEqual(store.roots(for: .codex), [])
    }

    func testLooksLikeHomeKnowsEachAgentsLayout() throws {
        let root = home.appendingPathComponent("layouts", isDirectory: true)
        for (sub, id): (String, ProviderID) in [
            ("a/projects", .claudeCode), ("b/sessions", .codex),
            ("c/data/sessions", .cline), ("d/session-state", .copilot)
        ] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(sub), withIntermediateDirectories: true)
            let base = root.appendingPathComponent(String(sub.prefix(1)))
            XCTAssertTrue(BuiltInRoots.looksLikeHome(for: id, root: base), sub)
        }
        XCTAssertFalse(BuiltInRoots.looksLikeHome(for: .claudeCode, root: root))
    }
}
