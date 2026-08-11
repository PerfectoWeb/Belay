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

    init(state: AppState) {
        self.state = state
        super.init()
    }

    var isVisible: Bool { popover?.isShown ?? false }

    /// Lets the tests assert that closing the panel really drops the SwiftUI
    /// view, which is the part with a measurable cost if it regresses.
    var hostedControllerForTesting: NSViewController? { popover?.contentViewController }

    /// The size the panel is actually presenting at.
    var contentSizeForTesting: NSSize? { popover?.contentSize }

    func show(relativeTo button: NSStatusBarButton) {
        guard !isVisible else { return }
        let popover = makePopover()
        self.popover = popover

        // Without activating first the popover opens behind the frontmost app
        // and never takes key, which kills keyboard navigation in the panel.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func hide() {
        popover?.close()
        teardown()
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        guard !isVisible else {
            hide()
            return
        }
        show(relativeTo: button)
    }

    private func makePopover() -> NSPopover {
        let root = PanelView(
            state: state,
            onDismiss: { [weak self] in self?.hide() },
            onHeightChange: { [weak self] in self?.grow(to: $0) })
        let hosting = NSHostingController(rootView: root)
        // Deliberately not `.preferredContentSize`. Letting SwiftUI drive the
        // popover's size means AppKit resizes the window on every frame of a
        // SwiftUI height animation, one frame behind — which is the visible
        // judder that made the header jump while a disclosure opened below it.
        // The content is laid out at its final size straight away and the
        // *window* is what animates, so growth is downward and nothing above
        // the disclosure can move.
        hosting.sizingOptions = []
        hosting.view.setAccessibilityLabel(String(localized: "\(Branding.appName) panel"))

        let popover = NSPopover()
        popover.contentViewController = hosting
        // With SwiftUI no longer driving the size, the popover has none until the
        // first height measurement arrives — and that is one layout pass too
        // late to open with. Seed it from the view's own fitting size.
        hosting.view.layoutSubtreeIfNeeded()
        popover.contentSize = NSSize(
            width: PanelView.width,
            height: max(hosting.view.fittingSize.height, PanelView.minimumHeight))
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        return popover
    }

    /// Resizes the popover to a new content height, in one step.
    ///
    /// Deliberately **not** animated. Three things wanted to animate this at
    /// once — SwiftUI laying the content out, `NSAnimationContext` easing the
    /// content size, and AppKit repositioning the popover against its anchor —
    /// and each disagreed with the others by a frame, which is what the judder
    /// was. The height measurement also arrives more than once per update, so an
    /// eased resize could be interrupted by the next one mid-flight.
    ///
    /// A menu bar panel opens, does its job and closes; the disclosure is the
    /// only thing in it that resizes, and one clean step is better than a
    /// smoothness that shakes. If this is ever animated again it has to be the
    /// *only* animator — which means driving the window frame directly, not
    /// asking three layers to cooperate.
    private func grow(to height: CGFloat) {
        guard let popover else { return }
        guard abs(popover.contentSize.height - height) > 0.5 else { return }
        popover.contentSize = NSSize(width: PanelView.width, height: height)
    }

    /// Drops the hosting controller so nothing SwiftUI-shaped survives a close.
    private func teardown() {
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
