import BelayCore
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
