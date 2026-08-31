import BelayCore
import BelayHookBridge
import XCTest

@testable import Belay

/// A graceful quit takes Belay's hook entries out of the agents' settings;
/// the next launch puts back exactly what the quit removed, at whatever port
/// the receiver came up on. Fully sandboxed in a scratch tree.
@MainActor
final class ParkedHooksTests: XCTestCase {
    private var root: URL!
    private var paths: BridgePaths!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("belay-parked-\(UUID().uuidString)", isDirectory: true)
        for sub in [".claude", "support"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        paths = BridgePaths(
            support: root.appendingPathComponent("support"),
            claudeSettings: root.appendingPathComponent(".claude/settings.json"),
            codexHome: root.appendingPathComponent(".codex"),
            clineHome: root.appendingPathComponent(".cline"))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func settingsText() -> String {
        (try? String(contentsOf: paths.claudeSettings, encoding: .utf8)) ?? ""
    }

    func testQuitParksAndRelaunchRestores() async throws {
        let first = PreciseDetection(paths: paths)
        _ = await first.start()
        XCTAssertTrue(first.install(), "install under consent")
        XCTAssertTrue(settingsText().contains("/hook?src=belay"))

        first.parkForQuit()
        XCTAssertFalse(settingsText().contains("/hook?src=belay"), "quit leaves no hooks behind")
        XCTAssertEqual(ParkedHooksStore(paths: paths).load(), ParkedHooks(claude: true))
        await first.stop()

        let second = PreciseDetection(paths: paths)
        _ = await second.start()
        XCTAssertTrue(settingsText().contains("/hook?src=belay"), "relaunch restores them")
        XCTAssertTrue(second.isInstalled)
        XCTAssertNil(ParkedHooksStore(paths: paths).load(), "the record is consumed")
        await second.stop()
    }

    func testNothingInstalledParksNothing() async throws {
        let precise = PreciseDetection(paths: paths)
        _ = await precise.start()
        precise.parkForQuit()
        XCTAssertNil(ParkedHooksStore(paths: paths).load())
        await precise.stop()
    }
}
