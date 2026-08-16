import AppKit
import BelaySettings
import BelaySupport
import SwiftUI

/// Presents `OnboardingView` once, on first launch.
///
/// A plain `NSWindow` rather than a SwiftUI `Window` scene: this app is
/// `LSUIElement`, so it has no normal window lifecycle to hang one off, and the
/// window has to be dismissable without leaving the app activated behind it.
@MainActor
final class OnboardingWindow: NSObject {
    private var window: NSWindow?
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
        super.init()
    }

    /// Shows the screen again from its first frame, whatever the preference
    /// says. For the workbench: the greeting only plays on a fresh window, so
    /// re-presenting is the only way to watch it twice.
    func presentAgain(providerReady: Bool, onGrantAccess: @escaping () -> Void) {
        dismiss()
        settings.hasCompletedOnboarding = false
        presentIfNeeded(providerReady: providerReady, onGrantAccess: onGrantAccess)
    }

    /// Shows the screen unless the user has already been through it.
    ///
    /// The caller cannot know whether the sandboxed build has its bookmark yet —
    /// `#if BELAY_MAS` means nothing where it is composed — so readiness is
    /// answered here, where `ClaudeAccess` can be asked. In the direct build it
    /// is always yes and the button says "Start watching", which is the truth
    /// there: nothing is being granted.
    func presentIfNeeded(providerReady: Bool, onGrantAccess: @escaping () -> Void) {
        guard !settings.hasCompletedOnboarding, window == nil else { return }

        let view = OnboardingView(
            providerReady: providerReady && ClaudeAccess.isGranted,
            onGrantAccess: { [weak self] in
                onGrantAccess()
                self?.dismiss()
            },
            onDismiss: { [weak self] in self?.dismiss() }
        )

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let host = NSHostingController(rootView: view)
        window.contentViewController = host
        // Sized from the content before anything is measured against it. The
        // window was created at `.zero` and `layoutIfNeeded()` was trusted to
        // have given it a size by the time `centre` read `frame.size`. On macOS
        // 26 it had; on macOS 15 it had not, so the centring arithmetic ran with
        // a size of zero and placed the window's bottom left corner on the
        // middle of the screen, which put the whole thing up and to the right.
        // Asking the hosting controller for its own fitting size does not
        // depend on when AppKit gets round to a layout pass.
        window.setContentSize(host.view.fittingSize)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.delegate = self
        // `center()` is not centred: AppKit puts a window slightly above the
        // middle, and it works from the screen the window happens to be on,
        // which for a window at .zero is whichever one contains the origin.
        // On a second display that is the wrong screen and the wrong height.
        centre(window)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// The middle of the screen the user is actually looking at, which is the
    /// one with the pointer on it, falling back to the main display.
    private func centre(_ window: NSWindow) {
        window.layoutIfNeeded()
        // Belt and braces: the size is set from the content above, and this is
        // the second chance to notice if it is still nothing rather than to
        // place the window somewhere absurd.
        guard window.frame.width > 0, window.frame.height > 0 else {
            Log.app.error("the welcome window had no size to centre; leaving it to AppKit")
            window.center()
            return
        }
        let pointer = NSEvent.mouseLocation
        let under = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
        let screen = under ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = window.frame.size
        window.setFrameOrigin(
            NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.midY - size.height / 2))
    }

    /// Marks onboarding done however it was closed, including the red button —
    /// showing it again on next launch would read as a bug.
    func dismiss() {
        settings.hasCompletedOnboarding = true
        window?.orderOut(nil)
        window?.delegate = nil
        window = nil
    }

    var isVisible: Bool { window?.isVisible ?? false }
}

extension OnboardingWindow: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        settings.hasCompletedOnboarding = true
        window = nil
    }
}
