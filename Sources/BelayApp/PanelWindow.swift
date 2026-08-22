import AppKit
import BelaySupport
import SwiftUI

/// Builds the one kind of window this app puts in front of somebody: a plain
/// `NSWindow` with no titlebar of its own, sized to its content and centred on
/// the screen they are looking at.
///
/// It exists because there are two of them now, the welcome screen and the
/// release notes, and both depend on the same two corrections that were
/// expensive to find. Duplicating them is how one window gets a fix and the
/// other keeps the bug.
///
/// This app is `LSUIElement`, so there is no normal window lifecycle to hang a
/// SwiftUI `Window` scene off, and both windows have to be dismissable without
/// leaving the app activated behind them.
@MainActor
enum PanelWindow {
    static func make<Content: View>(_ content: Content, delegate: NSWindowDelegate?) -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let host = NSHostingController(rootView: content)
        window.contentViewController = host
        // Sized from the content before anything is measured against it. The
        // window is created at `.zero` and `layoutIfNeeded()` cannot be trusted
        // to have given it a size by the time the centring arithmetic reads
        // `frame.size`. On macOS 26 it had; on macOS 15 it had not, so the sum
        // ran with a size of zero and put the window's bottom left corner in the
        // middle of the screen, which threw the whole thing up and to the right.
        // A hosting controller's fitting size does not depend on when AppKit
        // gets round to a layout pass.
        window.setContentSize(host.view.fittingSize)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        centre(window)
        return window
    }

    /// The middle of the screen the user is actually looking at, which is the
    /// one with the pointer on it, falling back to the main display.
    ///
    /// `center()` is not centred: AppKit puts a window slightly above the middle
    /// and works from the screen the window happens to be on, which for a window
    /// still at `.zero` is whichever one contains the origin. On a second
    /// display that is the wrong screen and the wrong height.
    static func centre(_ window: NSWindow) {
        window.layoutIfNeeded()
        // Belt and braces. The size is set from the content above; this is the
        // second chance to notice it is still nothing, rather than to place the
        // window somewhere absurd.
        guard window.frame.width > 0, window.frame.height > 0 else {
            Log.app.error("a panel window had no size to centre; leaving it to AppKit")
            window.center()
            return
        }
        let pointer = NSEvent.mouseLocation
        let under = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
        guard let frame = (under ?? NSScreen.main)?.visibleFrame else { return }
        let size = window.frame.size
        window.setFrameOrigin(
            NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
    }
}
