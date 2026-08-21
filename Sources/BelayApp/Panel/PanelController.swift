import AppKit
import SwiftUI

/// Hosts `PanelView` in an `NSPopover` hung off the status item.
///
/// AppKit rather than `MenuBarExtra` for the reasons in docs/05 (focus,
/// dismissal and right-click all still misbehave in the SwiftUI version).
///
/// The popover and its hosting controller are built on `show` and thrown away
/// on close, on purpose. A SwiftUI view that outlives the closed panel keeps
/// observing `AppState` and re-rendering behind the user's back, which docs/08
/// lists as a standard way to lose the idle CPU budget.
@MainActor
final class PanelController: NSObject {
    private let state: AppState
    private var popover: NSPopover?
    /// Watches clicks in other applications while the panel is up.
    ///
    /// `.transient` is supposed to do this, and does — until another window
    /// of ours becomes key while the popover is open. The duration menu is
    /// one such window, the Settings window another; after either, AppKit
    /// stops treating the popover as transient and a click on the desktop or
    /// in another app leaves the panel hanging. A global monitor sees exactly
    /// those clicks (events bound for other apps) and nothing of ours, so the
    /// status item's own toggle and the menu's items are unaffected.
    private var outsideClicks: Any?

    init(state: AppState) {
        self.state = state
        super.init()
    }

    var isVisible: Bool { popover?.isShown ?? false }

    /// Lets the tests assert that closing the panel really drops the SwiftUI
    /// view, which is the part with a measurable cost if it regresses.
    var hostedControllerForTesting: NSViewController? { popover?.contentViewController }

    /// The size the panel is actually presenting at.
    var contentSizeForTesting: NSSize? {
        guard let popover else { return nil }
        let preferred = popover.contentViewController?.preferredContentSize ?? .zero
        return preferred.height > 0 ? preferred : popover.contentSize
    }

    func show(relativeTo button: NSStatusBarButton) {
        guard !isVisible else { return }
        let popover = makePopover()
        self.popover = popover

        // Without activating first the popover opens behind the frontmost app
        // and never takes key, which kills keyboard navigation in the panel.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        popover.contentViewController?.view.window?.makeKey()
        watchOutsideClicks()
    }

    func hide() {
        popover?.close()
        teardown()
    }

    private func watchOutsideClicks() {
        guard outsideClicks == nil else { return }
        outsideClicks = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        guard !isVisible else {
            hide()
            return
        }
        show(relativeTo: button)
    }

    private func makePopover() -> NSPopover {
        let root = PanelView(state: state, onDismiss: { [weak self] in self?.hide() })
        let hosting = NSHostingController(rootView: root)
        // SwiftUI owns the size, through the one path AppKit documents.
        //
        // This used to be `[]`, with the view measuring itself through a
        // preference and the controller pushing the result into the popover.
        // That was written to stop the panel juddering while a disclosure
        // opened, and it did — on the macOS it was written on. On macOS 15 the
        // seed and the measurement never agreed, and the panel opened shorter
        // than its contents: the first line was cut off above the top edge and
        // the footer below the bottom one.
        //
        // The judder it was avoiding has its own guard now: `PanelAnimationTests`
        // scans this folder and fails if anything animates a layout, so nothing
        // is left to move a height behind AppKit's back, and the supported path
        // is the one that cannot disagree with itself.
        hosting.sizingOptions = [.preferredContentSize]
        hosting.view.setAccessibilityLabel(String(localized: "\(Branding.appName) panel"))

        let popover = NSPopover()
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        return popover
    }

    /// Drops the hosting controller so nothing SwiftUI-shaped survives a close.
    private func teardown() {
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        outsideClicks = nil
        guard let popover else { return }
        popover.delegate = nil
        popover.contentViewController = nil
        self.popover = nil
    }

    deinit {
        MainActor.assumeIsolated {
            popover?.close()
            popover?.contentViewController = nil
            popover = nil
        }
    }
}

extension PanelController: NSPopoverDelegate {
    /// `.transient` popovers close themselves when the user clicks elsewhere,
    /// so this is the only place guaranteed to run on every dismissal path.
    func popoverDidClose(_ notification: Notification) {
        teardown()
    }
}
