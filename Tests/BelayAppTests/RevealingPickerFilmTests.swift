import AppKit
import BelaySettings
import SwiftUI
import XCTest

@testable import Belay

/// The filming stand for the sleep-delay pop-up, in the shape the other live
/// stands use: put the real control on the real screen, hold it there, and let
/// something outside the process take the picture.
///
/// It has to be this way round. A menu draws in a window of its own and tracks
/// on its own run loop, so no view snapshot can reach it — a detached control
/// caches its bezel and nothing else, which is enough ink to fool a check that
/// only asks whether anything was drawn. What the menu *contains* is asserted
/// in `RevealingPickerTests`; this is for looking at it.
///
/// `BELAY_FILM_PICKER` picks the state: `resting`, `shift`, or `long`. Skipped
/// without it, because it needs a screen and four seconds.
@MainActor
final class RevealingPickerFilmTests: XCTestCase {
    func testHoldTheMenuOpenForTheCamera() throws {
        let state = ProcessInfo.processInfo.environment["BELAY_FILM_PICKER"]
        try XCTSkipIf(state == nil, "set BELAY_FILM_PICKER to resting, shift or long")

        let selection: TimeInterval = state == "long" ? 1800 : 60
        let shiftHeld = state == "shift"

        var value = selection
        let picker = RevealingPicker(
            selection: Binding(get: { value }, set: { value = $0 }),
            base: SettingsPresets.gracePeriods,
            extended: SettingsPresets.longGracePeriods,
            label: { DurationChoice.label($0) },
            accessibilityLabel: "Sleep delay")
        let coordinator = picker.makeCoordinator()
        let button = NSPopUpButton(
            frame: NSRect(x: 30, y: 30, width: 180, height: 26), pullsDown: false)
        coordinator.button = button
        coordinator.build(
            on: button, all: SettingsPresets.allGracePeriods, label: { DurationChoice.label($0) })
        coordinator.select(selection, on: button)

        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 400, width: 240, height: 86),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Sleep delay"
        window.contentView?.addSubview(button)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        // The keyboard is the one thing a test cannot hold down, so the reveal
        // rule is called directly — it is the control's own, unmodified.
        coordinator.reveal(shiftHeld: shiftHeld)

        // Tell the camera the menu is about to open. Written before the click
        // because the click does not return until the menu is dismissed.
        if let marker = ProcessInfo.processInfo.environment["BELAY_FILM_READY"] {
            try? "ready".write(toFile: marker, atomically: true, encoding: .utf8)
        }

        // A timer in the common run-loop modes: a menu tracks on its own loop,
        // and nothing scheduled the ordinary way runs while it is open.
        let closer = Timer(timeInterval: 20, repeats: false) { _ in
            MainActor.assumeIsolated { button.menu?.cancelTracking() }
        }
        RunLoop.main.add(closer, forMode: .common)
        button.performClick(nil)
        closer.invalidate()
    }
}
