import AppKit
import BelayCore

/// The Always-on duration menu, with a second, finer set of choices behind
/// the Shift key — the way the Apple menu's "Shut Down…" loses its ellipsis
/// under Option. Seven choices without Shift, fourteen with, and the change
/// happens live: hold Shift before clicking or while the menu is open, and
/// the extra rows appear in place.
///
/// AppKit, not SwiftUI's `Menu`, because only `NSMenu` lets a menu change
/// while it is being tracked. The extra rows are ordinary items kept hidden,
/// and a local `flagsChanged` monitor unhides them while Shift is down.
@MainActor
final class DurationMenu: NSObject, NSMenuDelegate {
    /// Always offered.
    static let base: [TimeInterval] = [900, 1800, 3600, 7200, 14400, 28800, 43200]
    /// Offered only under Shift, interleaved with the base set in order.
    static let extra: [TimeInterval] = [2700, 10800, 18000, 21600, 25200, 36000, 50400]

    private let menu = NSMenu()
    private var monitor: Any?
    private var current: TimeInterval?
    private let choose: (TimeInterval?) -> Void

    init(choose: @escaping (TimeInterval?) -> Void) {
        self.choose = choose
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        build()
    }

    /// Drops the menu from `view`'s bottom-left corner, like a pop-up button.
    /// `shiftHeld` is read from the keyboard unless a test says otherwise.
    func show(from view: NSView, current: TimeInterval?, shiftHeld: Bool? = nil) {
        self.current = current
        for item in menu.items {
            guard let value = item.representedObject as? TimeInterval? else { continue }
            item.state = value == current ? .on : .off
        }
        reveal(shiftHeld: shiftHeld ?? NSEvent.modifierFlags.contains(.shift))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.minY - 4), in: view)
    }

    /// For the filming stand: the menu tracks on its own loop, so something
    /// outside it has to put it away.
    func dismissForTesting() {
        menu.cancelTracking()
    }

    private func build() {
        let unbounded = NSMenuItem(
            title: String(localized: "Until turned off"), action: #selector(pick(_:)), keyEquivalent: "")
        unbounded.target = self
        unbounded.representedObject = Optional<TimeInterval>.none as Any
        menu.addItem(unbounded)
        for seconds in (Self.base + Self.extra).sorted() {
            let item = NSMenuItem(
                title: DurationChoice.label(seconds), action: #selector(pick(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = Optional(seconds) as Any
            item.isHidden = Self.extra.contains(seconds)
            menu.addItem(item)
        }
    }

    private func reveal(shiftHeld: Bool) {
        for item in menu.items {
            guard let value = item.representedObject as? TimeInterval?, let seconds = value,
                Self.extra.contains(seconds)
            else { continue }
            item.isHidden = !shiftHeld
        }
    }

    @objc private func pick(_ sender: NSMenuItem) {
        // Two layers of optional: the cast fails for a stray item, and the
        // "until turned off" row carries a genuine nil.
        let value = (sender.representedObject as? TimeInterval?).flatMap { $0 }
        choose(value)
    }

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let shift = event.modifierFlags.contains(.shift)
            MainActor.assumeIsolated { self?.reveal(shiftHeld: shift) }
            return event
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
