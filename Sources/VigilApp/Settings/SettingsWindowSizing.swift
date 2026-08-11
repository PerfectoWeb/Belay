import AppKit
import SwiftUI
import VigilProviders

/// How tall the Settings window is, and how it gets there.
///
/// Split out of `SettingsWindow` only because that file had grown past what one
/// file should hold. It is one question — how tall does this pane want to be —
/// plus the two ways of moving to it.
extension SettingsWindow {
    /// The pane's own idea of how tall it wants to be, measured at the fixed
    /// window width. Clamped so a pane that grows without bound — a long list of
    /// watched tools — scrolls instead of running off the screen.
    func height(for pane: SettingsPane, watching: [GenericTarget]? = nil) -> CGFloat {
        let probe = NSHostingView(rootView: view(for: pane, watching: watching).content)
        // Without this the hosting view answers with whatever it had before it
        // laid anything out, which for the Providers pane is a height that
        // ignores the tiles entirely.
        probe.layoutSubtreeIfNeeded()
        let fitting = probe.fittingSize.height
        guard fitting > 1 else { return pane.fallbackHeight }
        // Bounded by the screen, not by a fixed number: adding a fourth watched
        // tool should make the window taller, the way a Finder window grows, not
        // introduce a scroller. The ceiling only exists so the window cannot run
        // off a short display.
        let ceiling =
            (window?.screen ?? NSScreen.main)
            .map { $0.visibleFrame.height - 80 } ?? 640
        return min(max(fitting, 160), ceiling)
    }

    /// Grows downwards so the switcher stays put while the window changes size,
    /// which is what makes the animation read as the pane changing rather than
    /// the window jumping.
    func resize(
        _ window: NSWindow, to height: CGFloat, animated: Bool, through target: NSWindow? = nil
    ) {
        let content = NSSize(width: SettingsPane.width, height: height)
        window.contentMinSize = content
        window.contentMaxSize = content
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content))
        frame.origin.x = window.frame.origin.x
        frame.origin.y = window.frame.maxY - frame.height
        (target ?? window).setFrame(frame, display: true, animate: animated)
    }

    /// Adding a watched tool makes the pane taller, and a preferences window that
    /// answers that with a scroller is one where the thing you just added is
    /// below the fold. The window grows instead, the way a Finder window does.
    ///
    /// Measured against the targets that were just set rather than against the
    /// controller's, which has not necessarily caught up yet.
    func refit(with targets: [GenericTarget]) {
        guard let window, pane == .providers else { return }
        let wanted = height(for: pane, watching: targets)
        // Against the size the window is committed to, not against its frame:
        // the frame is still travelling there through the animator.
        guard abs(window.contentMinSize.height - wanted) > 1 else { return }

        // `setFrame(display:animate:)` runs its animation by blocking the run
        // loop, which would hold the tile's own animation still for a third of a
        // second and land it as a jump. The animator proxy does not.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            resize(window, to: wanted, animated: false, through: window.animator())
        }
    }
}
