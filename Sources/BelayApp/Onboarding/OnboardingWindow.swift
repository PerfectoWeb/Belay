import AppKit
import BelaySettings
import SwiftUI

/// Presents `OnboardingView` once, on first launch.
///
/// The window itself comes from `PanelWindow`, which the release-notes screen
/// shares: same chrome, same sizing, same centring, and one place to fix any of
/// them.
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

        let window = PanelWindow.make(view, delegate: self)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Marks onboarding done however it was closed, including the red button —
    /// showing it again on next launch would read as a bug.
    ///
    /// The version goes down with it. Somebody who has just been shown the whole
    /// product does not need to be told, on their next launch, what changed in
    /// the only version they have ever run.
    func dismiss() {
        settings.hasCompletedOnboarding = true
        settings.lastSeenVersion = Branding.version
        silence()
        window?.orderOut(nil)
        window?.delegate = nil
        window = nil
    }

    /// The long sounds outlive any one picture on purpose — the recordings by
    /// design, the typing bed by being seven seconds of texture — so the
    /// window going away is the one thing that must cut them all off. The
    /// short strikes are left alone: a pop's tail is over before the window
    /// finishes ordering out.
    private func silence() {
        Feedback.stop(.welcomeSpell)
        Feedback.stop(.welcomeCinematic)
        Feedback.stop(.welcomeTyping)
    }

    var isVisible: Bool { window?.isVisible ?? false }
}

extension OnboardingWindow: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        settings.hasCompletedOnboarding = true
        settings.lastSeenVersion = Branding.version
        silence()
        window = nil
    }
}
