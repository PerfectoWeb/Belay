import AppKit
import BelaySettings
import BelayCore
import XCTest

@testable import Belay

/// Puts the real panel in a real popover on the real screen and switches the
/// mode, so the transition can be filmed from outside. Not a gate test: it
/// runs only with `BELAY_LIVE_POPOVER` set, shows a window in the top-left
/// corner for a few seconds, and asserts nothing — the frames are the result.
@MainActor
final class LivePopoverTests: XCTestCase {
    func testSwitchModeOnScreen() throws {
        guard ProcessInfo.processInfo.environment["BELAY_LIVE_POPOVER"] != nil else {
            throw XCTSkip("set BELAY_LIVE_POPOVER to film the panel")
        }
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }

        let app = AppState()
        app.mode = .auto
        app.apply(
            CoordinatorSnapshot(
                state: .armed, sessions: [], activities: [:], holdReason: nil, holdingSince: nil),
            totalAwake: 60)
        // The real wiring's shape: the mode change lands in the snapshot.
        app.onModeChange = { mode in
            app.apply(
                CoordinatorSnapshot(
                    state: mode == .alwaysOn ? .alwaysOn : .armed, sessions: [], activities: [:],
                    holdReason: mode == .alwaysOn ? .alwaysOn : nil, holdingSince: nil),
                totalAwake: 60)
        }

        let anchor = NSWindow(
            contentRect: NSRect(x: screen.frame.minX + 40, y: screen.frame.maxY - 60, width: 40, height: 20),
            styleMask: [.borderless], backing: .buffered, defer: false)
        anchor.level = .floating
        anchor.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 40, height: 20))
        anchor.contentView?.addSubview(button)

        let panel = PanelController(state: app)
        panel.show(relativeTo: button)
        spin(2.0)

        let picker = PanelModePicker(state: app)
        picker.selectForTesting(.alwaysOn)
        spin(1.5)
        picker.selectForTesting(.off)
        spin(1.5)

        panel.hide()
        anchor.orderOut(nil)
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}

/// Puts the dim clock on the real screen for a few seconds so it can be
/// photographed. Same contract as the popover run: opt-in, asserts nothing.
@MainActor
final class LiveDimClockTests: XCTestCase {
    func testClockOnScreen() throws {
        guard ProcessInfo.processInfo.environment["BELAY_LIVE_POPOVER"] != nil else {
            throw XCTSkip("set BELAY_LIVE_POPOVER to film the clock")
        }
        let clock = DimClock()
        let timer = AlwaysOnTimer(duration: 3600, deadline: Date() + 1234)
        clock.sync(dimmed: true, enabled: true, timer: timer)
        RunLoop.main.run(until: Date().addingTimeInterval(4))
        clock.hide()
    }
}

/// The real What's New window on the real screen, for a photograph.
@MainActor
final class LiveWhatsNewTests: XCTestCase {
    func testCardOnScreen() throws {
        guard ProcessInfo.processInfo.environment["BELAY_LIVE_POPOVER"] != nil else {
            throw XCTSkip("set BELAY_LIVE_POPOVER to film the card")
        }
        let window = WhatsNewWindow(settings: SettingsStore())
        window.present()
        // Long enough to be looked at when a person asked to see it.
        let seconds = Double(ProcessInfo.processInfo.environment["BELAY_LIVE_SECONDS"] ?? "4") ?? 4
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        window.dismiss()
    }
}

/// The real Settings window opened straight onto Agents, for filming the
/// first seconds of the switches. Uses the real `SettingsWindow` — the lazy
/// `LoginItem`, the delegate callbacks, all of it — because the stall being
/// hunted lives in that wiring, not in the tile alone.
@MainActor
final class LiveAgentsPaneTests: XCTestCase {
    func testAgentsPaneOnScreen() throws {
        guard ProcessInfo.processInfo.environment["BELAY_LIVE_POPOVER"] != nil else {
            throw XCTSkip("set BELAY_LIVE_POPOVER to film the pane")
        }
        let settings = SettingsStore(suiteName: "live-agents-\(UUID().uuidString)")
        // One on, one off: the report is that off switches read as on for the
        // first seconds, so the stand needs an off switch to catch lying.
        settings.enabledProviders = [.claudeCode]
        let app = AppState()
        app.apply(providers: [
            ProviderStatus(
                descriptor: ProviderDescriptor(
                    id: .claudeCode, displayName: "Claude Code", summary: "", symbolName: "sparkles",
                    supportsPreciseDetection: true),
                availability: .ready, isEnabled: true, lastSignal: Date().addingTimeInterval(-300)),
            ProviderStatus(
                descriptor: ProviderDescriptor(
                    id: .codex, displayName: "Codex", summary: "", symbolName: "curlybraces",
                    supportsPreciseDetection: false),
                availability: .ready, isEnabled: false, lastSignal: nil),
        ])
        let window = SettingsWindow(
            settings: settings, state: app, precise: PreciseDetection(),
            targets: { [] }, statistics: { UsageStatistics() }, onTargetsChanged: { _ in })
        window.show(pane: .providers)
        window.window?.setFrameOrigin(NSPoint(x: 60, y: 200))
        // The window number lets the film be taken per-window from outside
        // (`screencapture -l`), which survives the user's own windows sitting
        // on top of the stand.
        if let folder = ProcessInfo.processInfo.environment["BELAY_FRAMES"],
            let number = window.window?.windowNumber
        {
            try? "\(number)".write(
                to: URL(fileURLWithPath: folder).appendingPathComponent("wid.txt"),
                atomically: true, encoding: .utf8)
        }
        let seconds = Double(ProcessInfo.processInfo.environment["BELAY_LIVE_SECONDS"] ?? "4") ?? 4
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        window.close()
    }
}

/// The duration menu on the real screen, plain and with Shift, for a photo.
@MainActor
final class LiveDurationMenuTests: XCTestCase {
    func testMenuOnScreen() throws {
        guard ProcessInfo.processInfo.environment["BELAY_LIVE_POPOVER"] != nil else {
            throw XCTSkip("set BELAY_LIVE_POPOVER to film the menu")
        }
        guard let screen = NSScreen.main else { throw XCTSkip("no screen") }
        let anchor = NSWindow(
            contentRect: NSRect(x: screen.frame.minX + 60, y: screen.frame.maxY - 80, width: 120, height: 20),
            styleMask: [.borderless], backing: .buffered, defer: false)
        anchor.level = .floating
        anchor.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 20))
        anchor.contentView?.addSubview(view)

        for shift in [false, true] {
            let menu = DurationMenu(choose: { _ in })
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { menu.dismissForTesting() }
            menu.show(from: view, current: 3600, shiftHeld: shift)
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        }
        anchor.orderOut(nil)
    }
}
