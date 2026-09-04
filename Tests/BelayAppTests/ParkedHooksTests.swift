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

    /// The Cline half of the same round trip: script files in ~/.cline/hooks
    /// leave on quit and come back on launch.
    func testClineParksAndRestoresToo() async throws {
        let first = PreciseDetection(paths: paths)
        _ = await first.start()
        XCTAssertTrue(first.installCline())
        XCTAssertTrue(ClineHookInstaller(paths: paths).isInstalled())

        first.parkForQuit()
        XCTAssertFalse(ClineHookInstaller(paths: paths).isInstalled())
        XCTAssertEqual(ParkedHooksStore(paths: paths).load(), ParkedHooks(cline: true))
        await first.stop()

        let second = PreciseDetection(paths: paths)
        _ = await second.start()
        XCTAssertTrue(ClineHookInstaller(paths: paths).isInstalled(), "relaunch restores them")
        XCTAssertNil(ParkedHooksStore(paths: paths).load())
        await second.stop()
    }

    /// A restore that cannot write keeps what it owes: the record survives the
    /// failed launch and the next one pays it.
    func testFailedRestoreKeepsTheRecord() async throws {
        let first = PreciseDetection(paths: paths)
        _ = await first.start()
        XCTAssertTrue(first.install())
        first.parkForQuit()
        await first.stop()

        // A directory where the settings file should be: every write fails.
        try FileManager.default.removeItem(at: paths.claudeSettings)
        try FileManager.default.createDirectory(
            at: paths.claudeSettings, withIntermediateDirectories: false)
        let blocked = PreciseDetection(paths: paths)
        _ = await blocked.start()
        XCTAssertEqual(
            ParkedHooksStore(paths: paths).load(), ParkedHooks(claude: true),
            "a failed restore is still owed")
        await blocked.stop()

        try FileManager.default.removeItem(at: paths.claudeSettings)
        let third = PreciseDetection(paths: paths)
        _ = await third.start()
        XCTAssertTrue(settingsText().contains("/hook?src=belay"), "the next launch pays it")
        XCTAssertNil(ParkedHooksStore(paths: paths).load())
        await third.stop()
    }
}
