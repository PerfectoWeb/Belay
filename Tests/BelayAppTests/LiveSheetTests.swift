import AppKit
import BelayCore
import BelayHookBridge
import SwiftUI
import XCTest

@testable import Belay

/// The consent sheet on the real screen, against a scratch tree: the receiver
/// binds a throwaway port and every path points into the sandbox, so nothing
/// real is read beyond fonts and nothing real can be written.
@MainActor
final class LiveSheetTests: XCTestCase {
    func testSheetsOnScreen() async throws {
        guard ProcessInfo.processInfo.environment["BELAY_LIVE_POPOVER"] != nil else {
            throw XCTSkip("set BELAY_LIVE_POPOVER to film the sheet")
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sheet-stand-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = BridgePaths(
            support: root.appendingPathComponent("support", isDirectory: true),
            claudeSettings: root.appendingPathComponent(".claude/settings.json"),
            codexHome: root.appendingPathComponent(".codex", isDirectory: true),
            clineHome: root.appendingPathComponent(".cline", isDirectory: true))
        let precise = PreciseDetection(paths: paths)
        _ = await precise.start()

        let folder = ProcessInfo.processInfo.environment["BELAY_FRAMES"]
        let providers: [ProviderID] =
            ProcessInfo.processInfo.environment["BELAY_LIVE_SHEET"] == "cline"
            ? [.cline] : [.claudeCode, .codex, .cline]
        for provider in providers {
            let sheet = HookPreviewSheet(precise: precise, provider: provider) {}
            let window = NSWindow(
                contentRect: NSRect(x: 60, y: 200, width: 560, height: 620),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.contentViewController = NSHostingController(rootView: sheet)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            if let folder {
                try? "\(window.windowNumber)".write(
                    to: URL(fileURLWithPath: folder).appendingPathComponent(
                        "wid-\(provider.rawValue).txt"),
                    atomically: true, encoding: .utf8)
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            window.orderOut(nil)
        }
        await precise.stop()
    }
}
