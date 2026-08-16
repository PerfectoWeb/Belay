import AppKit
import BelaySettings
import BelaySupport
import SwiftUI

/// Presents `WhatsNewView` once, on the first launch after an update.
///
/// The decision about *whether* is `WhatsNewDecision`, which is pure and
/// tested. This type does the two things that need a running app: put a window
/// on screen, and write down that it happened.
///
/// Writing happens when the window opens, not when it closes. A crash between
/// the two would otherwise announce the same version again on the next launch,
/// and a screen that comes back after being dismissed reads as a bug in a way
/// that a screen missed once does not.
@MainActor
final class WhatsNewWindow: NSObject {
    private var window: NSWindow?
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
        super.init()
    }

    /// Shows the notes if this launch is the first on a newer version.
    ///
    /// - Parameter suppressed: true when the welcome screen is up. Both windows
    ///   are centred on the same screen, so the second one would land on top of
    ///   the first; and somebody being introduced to the app has no version to
    ///   be updated from. The decision returns nothing in that case anyway, and
    ///   this is the belt to its braces.
    func presentIfNeeded(suppressed: Bool = false) {
        guard window == nil, !suppressed else { return }

        let outcome = WhatsNewDecision.outcome(
            current: Branding.version,
            lastSeen: settings.lastSeenVersion,
            onboarded: settings.hasCompletedOnboarding)
        switch outcome {
        case .nothing:
            return
        case .recordOnly(let version):
            settings.lastSeenVersion = version
        case .show(let notes, let version):
            settings.lastSeenVersion = version
            Log.app.notice("showing release notes for \(version, privacy: .public)")
            present(notes)
        }
    }

    /// Opens the window whatever the preference says, for the workbench and for
    /// the About pane's "What's New" row. Nothing is recorded: asking to see the
    /// notes is not the same event as being shown them.
    func present(_ notes: [ReleaseNote] = ReleaseNotes.all) {
        // Nothing to say is not a window. The hero reads `notes.first`.
        guard !notes.isEmpty else { return }
        dismiss()
        let window = PanelWindow.make(
            WhatsNewView(notes: notes, onDismiss: { [weak self] in self?.dismiss() }),
            delegate: self)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        window?.orderOut(nil)
        window?.delegate = nil
        window = nil
    }

    var isVisible: Bool { window?.isVisible ?? false }
}

extension WhatsNewWindow: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
