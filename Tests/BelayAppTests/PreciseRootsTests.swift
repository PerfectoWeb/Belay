import BelayCore
import BelayHookBridge
import XCTest

@testable import Belay

/// Tier B across extra watched folders: hooks land in every root the agent is
/// watched in, and leave with the folder. Fully sandboxed in a scratch tree.
@MainActor
final class PreciseRootsTests: XCTestCase {
    private var root: URL!
    private var paths: BridgePaths!
    private var altClaude: URL!
    private var altCline: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("belay-precise-roots-\(UUID().uuidString)", isDirectory: true)
        altClaude = root.appendingPathComponent("claude-b", isDirectory: true)
        altCline = root.appendingPathComponent("cline-b", isDirectory: true)
        for sub in [".claude", "claude-b", "cline-b", "support"] {
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

    private func makePrecise() -> PreciseDetection {
        PreciseDetection(paths: paths) { [altClaude, altCline] id in
            switch id {
            case .claudeCode: return [altClaude!]
            case .cline: return [altCline!]
            default: return []
            }
        }
    }

    func testInstallAndUninstallCoverEveryRoot() async throws {
        let precise = makePrecise()
        _ = await precise.start()
        defer { Task { await precise.stop() } }

        XCTAssertTrue(precise.install())
        let defaultSettings = paths.claudeSettings.path
        let altSettings = altClaude.appendingPathComponent("settings.json").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: defaultSettings))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: altSettings),
            "the extra root missed its hooks")

        XCTAssertTrue(precise.installCline())
        let altHook = altCline.appendingPathComponent("hooks/TaskStart.sh").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: altHook))

        XCTAssertTrue(precise.uninstall())
        let altText = (try? String(contentsOfFile: altSettings, encoding: .utf8)) ?? ""
        XCTAssertFalse(altText.contains("src=belay"), "uninstall left hooks in the extra root")

        XCTAssertTrue(precise.uninstallCline())
        XCTAssertFalse(FileManager.default.fileExists(atPath: altHook))
    }

    func testAddedRootGetsHooksOnlyWhileEnabled() async throws {
        let late = root.appendingPathComponent("claude-late", isDirectory: true)
        try FileManager.default.createDirectory(at: late, withIntermediateDirectories: true)
        let precise = makePrecise()
        _ = await precise.start()
        defer { Task { await precise.stop() } }

        // Not installed yet: an added folder stays untouched (invariant 6).
        await precise.installIfEnabled(for: .claudeCode, at: late)
        let lateSettings = late.appendingPathComponent("settings.json").path
        XCTAssertFalse(FileManager.default.fileExists(atPath: lateSettings))

        // Installed: the consent covers every watched folder, late ones too.
        XCTAssertTrue(precise.install())
        await precise.installIfEnabled(for: .claudeCode, at: late)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lateSettings))

        // Removing the folder takes its hooks with it.
        await precise.uninstallHooks(for: .claudeCode, at: late)
        let text = (try? String(contentsOfFile: lateSettings, encoding: .utf8)) ?? ""
        XCTAssertFalse(text.contains("src=belay"))
    }
}
