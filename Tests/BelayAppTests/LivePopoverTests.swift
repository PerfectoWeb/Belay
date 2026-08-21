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

/// The veil and the clock together on the real screen, to be photographed.
@MainActor
final class LiveDimVeilTests: XCTestCase {
    func testVeilOnScreen() throws {
        guard ProcessInfo.processInfo.environment["BELAY_LIVE_POPOVER"] != nil else {
            throw XCTSkip("set BELAY_LIVE_POPOVER to film the veil")
        }
        let veil = DimVeil()
        let clock = DimClock()
        veil.show()
        clock.sync(dimmed: true, enabled: true, timer: AlwaysOnTimer(duration: 3600, deadline: Date() + 1234))
        RunLoop.main.run(until: Date().addingTimeInterval(4))
        clock.hide()
        veil.hide()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
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
        RunLoop.main.run(until: Date().addingTimeInterval(4))
        window.dismiss()
    }
}
