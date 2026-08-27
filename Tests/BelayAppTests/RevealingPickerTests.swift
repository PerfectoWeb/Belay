import AppKit
import BelaySettings
import SwiftUI
import XCTest

@testable import Belay

/// The sleep-delay pop-up's second half, and the rule that half needs.
///
/// The long delays are hidden until Shift is held. The one exception is the
/// row the setting currently holds: a control that hides its own value draws an
/// empty box, and somebody who chose 30 minutes last week has no way to know
/// why the pop-up went blank.
@MainActor
final class RevealingPickerTests: XCTestCase {
    /// The real coordinator, driving a real menu. The view's `makeNSView` needs
    /// a `Context` no test can build, so the two steps it performs — build the
    /// menu, then apply the reveal rule — are driven here directly.
    private func menu(selectedSeconds: TimeInterval, shiftHeld: Bool) -> NSPopUpButton {
        var value = selectedSeconds
        let picker = RevealingPicker(
            selection: Binding(get: { value }, set: { value = $0 }),
            base: SettingsPresets.gracePeriods,
            extended: SettingsPresets.longGracePeriods,
            label: { DurationChoice.label($0) },
            accessibilityLabel: "Sleep delay")
        let coordinator = picker.makeCoordinator()
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        coordinator.button = button
        coordinator.build(
            on: button, all: SettingsPresets.allGracePeriods, label: { DurationChoice.label($0) })
        coordinator.select(selectedSeconds, on: button)
        coordinator.reveal(shiftHeld: shiftHeld)
        return button
    }

    private func visibleTitles(_ button: NSPopUpButton) -> [String] {
        (button.menu?.items ?? []).filter { !$0.isHidden }.map(\.title)
    }

    func testRestingListShowsOnlyTheShortDelays() {
        let button = menu(selectedSeconds: 60, shiftHeld: false)
        XCTAssertEqual(
            visibleTitles(button), SettingsPresets.gracePeriods.map { DurationChoice.label($0) },
            "the resting pop-up offers the five short choices and nothing else")
    }

    func testShiftRevealsTheLongDelays() {
        let button = menu(selectedSeconds: 60, shiftHeld: true)
        XCTAssertEqual(
            visibleTitles(button), SettingsPresets.allGracePeriods.map { DurationChoice.label($0) },
            "every choice appears while Shift is held")
    }

    func testAChosenLongDelayStaysVisibleWithoutShift() {
        let button = menu(selectedSeconds: 1800, shiftHeld: false)
        XCTAssertTrue(
            visibleTitles(button).contains(DurationChoice.label(1800)),
            "the selected row must never be one of the hidden ones")
        XCTAssertEqual(
            visibleTitles(button).count, SettingsPresets.gracePeriods.count + 1,
            "and it is the only long delay showing")
        XCTAssertEqual(
            button.titleOfSelectedItem, DurationChoice.label(1800),
            "so the pop-up draws its own value rather than an empty box")
    }

    /// The other long delays stay hidden even when one of them is selected —
    /// choosing 30 minutes must not quietly unlock the whole list.
    func testTheOtherLongDelaysStayHidden() {
        let button = menu(selectedSeconds: 1800, shiftHeld: false)
        let titles = visibleTitles(button)
        XCTAssertFalse(titles.contains(DurationChoice.label(3600)))
        XCTAssertFalse(titles.contains(DurationChoice.label(900)))
    }
}
