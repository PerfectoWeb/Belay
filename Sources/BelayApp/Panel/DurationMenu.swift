import AppKit
import BelayCore

/// The Always-on duration menu, with a second, finer set of choices behind
/// the Shift key — the way the Apple menu's "Shut Down…" loses its ellipsis
/// under Option. Seven choices without Shift, fourteen with, and the change
/// happens live: hold Shift before clicking or while the menu is open, and
/// the extra rows appear in place.
///
/// AppKit, not SwiftUI's `Menu`, because only `NSMenu` lets a menu change
/// while it is being tracked. The extra rows are ordinary items kept hidden
/// and unhidden as Shift goes down and up. Watched by a timer, not an event
/// monitor: a menu tracks on its own event loop and a local monitor never
/// hears the key while it is open, which is how the first version looked
/// right and did nothing. A timer in the common run-loop modes ticks
/// through menu tracking.
///
/// The last row is "Custom…", for the length none of the presets are.
@MainActor
final class DurationMenu: NSObject, NSMenuDelegate {
    /// Always offered.
    static let base: [TimeInterval] = [900, 1800, 3600, 7200, 14400, 28800, 43200]
    /// Offered only under Shift, interleaved with the base set in order.
    static let extra: [TimeInterval] = [2700, 10800, 18000, 21600, 25200, 36000, 50400]

    private let menu = NSMenu()
    private var customItem: NSMenuItem?
    private var watcher: Timer?
    private var shiftShown = false
    private var current: TimeInterval?
    private let choose: (TimeInterval?) -> Void
    /// Asked to put up the custom-length dialog, after the menu has closed.
    var askCustom: (TimeInterval?) -> Void = { _ in }

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
            guard item.representedObject is TimeInterval? || item.representedObject == nil,
                item !== customItem, item.action != nil
            else { continue }
            let value = (item.representedObject as? TimeInterval?).flatMap { $0 }
            item.state = value == current ? .on : .off
        }
        // The check lands on Custom… exactly when the running length is one
        // no preset row owns.
        let presets = Self.base + Self.extra
        customItem?.state = current.map { !presets.contains($0) } == true ? .on : .off
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
        menu.addItem(.separator())
        let custom = NSMenuItem(
            title: String(localized: "Custom…"), action: #selector(pickCustom), keyEquivalent: "")
        custom.target = self
        // A marker, not a duration: without it the row cast as a nil duration
        // and wore a second checkmark whenever "until turned off" did.
        custom.representedObject = "custom"
        menu.addItem(custom)
        customItem = custom
    }

    private func reveal(shiftHeld: Bool) {
        shiftShown = shiftHeld
        for item in menu.items {
            guard let value = item.representedObject as? TimeInterval?, let seconds = value,
                Self.extra.contains(seconds)
            else { continue }
            item.isHidden = !shiftHeld
        }
    }

    @objc private func pickCustom() {
        // After the menu has gone, so the dialog is not fighting it for the
        // event loop.
        let current = current
        DispatchQueue.main.async { [weak self] in self?.askCustom(current) }
    }

    @objc private func pick(_ sender: NSMenuItem) {
        // Two layers of optional: the cast fails for a stray item, and the
        // "until turned off" row carries a genuine nil.
        let value = (sender.representedObject as? TimeInterval?).flatMap { $0 }
        choose(value)
    }

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let shift = NSEvent.modifierFlags.contains(.shift)
                if shift != self.shiftShown { self.reveal(shiftHeld: shift) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        watcher = timer
    }

    func menuDidClose(_ menu: NSMenu) {
        watcher?.invalidate()
        watcher = nil
    }
}
