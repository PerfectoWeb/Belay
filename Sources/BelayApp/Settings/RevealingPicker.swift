import AppKit
import SwiftUI

/// A pop-up whose longer choices are behind the Shift key.
///
/// The Always-on menu already works this way (`DurationMenu`), and the sleep
/// delay wanted the same shape for the same reason: five choices cover what
/// nearly everybody needs, three more exist for the case that does not, and
/// putting all eight in one list makes the ordinary decision harder for the
/// sake of the rare one. Hold Shift before opening the pop-up or while it is
/// open, and the extra rows appear in place.
///
/// AppKit rather than SwiftUI's `Picker`, because only `NSMenu` can change
/// while it is being tracked — a SwiftUI menu is built once when it opens and
/// cannot answer the keyboard afterwards.
///
/// One rule the Always-on menu does not need: a hidden row that is *selected*
/// is always shown. A control that draws itself blank because its own value is
/// behind a modifier key is worse than one that never hid anything.
struct RevealingPicker: NSViewRepresentable {
    @Binding var selection: TimeInterval
    /// Always visible.
    let base: [TimeInterval]
    /// Visible under Shift, or when it is what the setting currently holds.
    let extended: [TimeInterval]
    let label: (TimeInterval) -> String
    let accessibilityLabel: String
    var width: CGFloat = 160

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.pick(_:))
        button.setAccessibilityLabel(accessibilityLabel)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: width).isActive = true
        button.menu?.delegate = context.coordinator
        context.coordinator.button = button
        context.coordinator.build(on: button, all: (base + extended).sorted(), label: label)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        context.coordinator.select(selection, on: button)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, NSMenuDelegate {
        var parent: RevealingPicker
        weak var button: NSPopUpButton?
        // `nonisolated(unsafe)` only so `deinit` may invalidate it; every
        // other touch is main-actor menu-delegate code.
        nonisolated(unsafe) private var watcher: Timer?

        deinit {
            // The timer holds only a weak self, so a coordinator freed
            // mid-track would otherwise leave it ticking no-ops forever.
            watcher?.invalidate()
        }
        private var shiftShown = false

        init(_ parent: RevealingPicker) {
            self.parent = parent
        }

        func build(on button: NSPopUpButton, all: [TimeInterval], label: (TimeInterval) -> String) {
            button.removeAllItems()
            for seconds in all {
                let item = NSMenuItem(title: label(seconds), action: nil, keyEquivalent: "")
                item.representedObject = seconds
                button.menu?.addItem(item)
            }
            button.menu?.delegate = self
        }

        func select(_ seconds: TimeInterval, on button: NSPopUpButton) {
            reveal(shiftHeld: shiftShown)
            let index = button.menu?.items.firstIndex {
                ($0.representedObject as? TimeInterval) == seconds
            }
            if let index { button.selectItem(at: index) }
        }

        /// Hidden rows are the ones behind Shift — except the selected row,
        /// which has to stay visible or the pop-up shows an empty title.
        /// Not private: `RevealingPickerTests` drives this rather than a copy
        /// of it, which is the only way the test can catch it changing.
        func reveal(shiftHeld: Bool) {
            shiftShown = shiftHeld
            for item in button?.menu?.items ?? [] {
                guard let seconds = item.representedObject as? TimeInterval,
                    parent.extended.contains(seconds)
                else { continue }
                item.isHidden = !shiftHeld && seconds != parent.selection
            }
        }

        @objc func pick(_ sender: NSPopUpButton) {
            guard let seconds = sender.selectedItem?.representedObject as? TimeInterval else {
                return
            }
            parent.selection = seconds
        }

        // MARK: NSMenuDelegate

        func menuWillOpen(_ menu: NSMenu) {
            reveal(shiftHeld: RevealKey.isHeld)
            // If an unpaired open ever fires, the old timer must die with it
            // rather than tick unowned forever.
            watcher?.invalidate()
            // A timer in the common run-loop modes, not an event monitor: a
            // menu tracks on its own loop and a local monitor never hears the
            // key while it is open.
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let shift = RevealKey.isHeld
                    if shift != self.shiftShown { self.reveal(shiftHeld: shift) }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            watcher = timer
        }

        func menuDidClose(_ menu: NSMenu) {
            watcher?.invalidate()
            watcher = nil
            // Back to the resting state, so the next open starts honest.
            reveal(shiftHeld: false)
        }
    }
}
