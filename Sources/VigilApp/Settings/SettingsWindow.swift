import AppKit
import SwiftUI
import VigilProviders
import VigilSettings

/// Owns the Settings window directly instead of going through SwiftUI's
/// `Settings` scene.
///
/// The scene approach did not work here and the failure was silent: neither the
/// panel's Settings button nor Cmd+, produced a window, because a `LSUIElement`
/// app has no menu bar for the standard Settings item to live in and nothing
/// ends up responding to `showSettingsWindow:`. Owning an `NSWindow` is the same
/// pattern `OnboardingWindow` already uses, and it can be tested.
///
/// The pane switcher is a real `NSToolbar` in `.preference` style: icon over
/// label, centred title following the selection, window height animating to the
/// pane. That is the Terminal and Mail shape, and it is the shape this window
/// went back to after two attempts at drawing it ourselves — see
/// `docs/design/settings-tabs-drawn-strip.swift.txt` for what was tried and why
/// the system control won. Unlike a SwiftUI `TabView` it cannot collapse into an
/// overflow chevron or resize the window behind our back.
@MainActor
final class SettingsWindow: NSObject {
    private(set) var window: NSWindow?
    private(set) var pane: SettingsPane = .general
    private var hosting: NSHostingController<SettingsView>?
    private let settings: SettingsStore
    private let state: AppState
    private let precise: PreciseDetection
    private let targets: () -> [GenericTarget]
    private let statistics: () -> UsageStatistics
    private let onTargetsChanged: ([GenericTarget]) -> Void
    /// Owned here so the toggle survives a pane switch, and so the window can
    /// re-read macOS when it comes back to the front.
    ///
    /// Lazy on purpose: constructing it asks `backgroundtaskmanagementd` for the
    /// login-item status over XPC, on the main thread. That daemon is slowest to
    /// answer during login — exactly when Vigil launches if "Open at login" is
    /// on — and nobody has opened Settings yet.
    private lazy var loginItem = LoginItem()
    /// Alive only while a pane that moves is open and frontmost.
    private var refreshTimer: Timer?
    /// Tracked from the delegate callbacks rather than read off `isKeyWindow`,
    /// so there is exactly one thing to get right and a test can drive it.
    private var isFrontmost = false
    var isRefreshingForTesting: Bool { refreshTimer?.isValid == true }
    let updates = ReleaseChecker()

    init(
        settings: SettingsStore,
        state: AppState,
        precise: PreciseDetection,
        targets: @escaping () -> [GenericTarget],
        statistics: @escaping () -> UsageStatistics,
        onTargetsChanged: @escaping ([GenericTarget]) -> Void
    ) {
        self.settings = settings
        self.state = state
        self.precise = precise
        self.targets = targets
        self.onTargetsChanged = onTargetsChanged
        self.statistics = statistics
        super.init()
    }

    static let windowIdentifier = NSUserInterfaceItemIdentifier("vigil.settings.window")

    var isVisible: Bool { window?.isVisible ?? false }

    /// `pane` lets the menu open straight onto Statistics instead of making the
    /// user find it.
    func show(pane requested: SettingsPane? = nil) {
        if let window {
            // Unconditionally, even when the pane asked for is the one already
            // showing: `select` is what rebuilds the SwiftUI view, and returning
            // early here is why Statistics re-entered from the menu kept showing
            // whatever numbers were current when the window was last built.
            select(requested ?? pane)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        if let requested { pane = requested }

        let hosting = NSHostingController(rootView: view(for: pane))
        // With SwiftUI driving the window size (the default `sizingOptions`) it
        // resized the window back down under us, so setting a size had no
        // effect. This takes the size decision away from SwiftUI; `select`
        // measures each pane and drives the window itself.
        hosting.sizingOptions = []

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsPane.width, height: pane.fallbackHeight),
            // No miniaturise: a preferences window in the Dock is a
            // preferences window you have lost.
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.identifier = Self.windowIdentifier
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.toolbarStyle = .preference
        window.toolbar = makeToolbar()
        self.window = window
        self.hosting = hosting

        select(pane, animated: false)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func select(_ pane: SettingsPane, animated: Bool = true) {
        self.pane = pane
        guard let window, let hosting else { return }
        hosting.rootView = view(for: pane)
        window.title = pane.title
        window.toolbar?.selectedItemIdentifier = pane.itemIdentifier
        resize(window, to: height(for: pane), animated: animated)
        retimeRefresh()
    }

    func close() {
        window?.close()
    }

    /// Rebuilds the pane in place, leaving the window's size alone — remeasuring
    /// on a tick would animate the window under the user.
    private func refreshContent() {
        hosting?.rootView = view(for: pane)
    }

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "vigil.settings.toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        return toolbar
    }

    /// Statistics is the only pane whose numbers move while it is on screen, and
    /// nothing ticks unless it is both open and frontmost: a Settings window left
    /// behind another app costs exactly as much as a closed one (docs/08).
    private func retimeRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard pane == .statistics, isFrontmost else { return }
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshContent() }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func view(for pane: SettingsPane, watching: [GenericTarget]? = nil) -> SettingsView {
        SettingsView(
            pane: pane,
            settings: settings,
            state: state,
            precise: precise,
            targets: watching ?? targets(),
            statistics: statistics(),
            loginItem: loginItem,
            updates: updates,
            onTargetsChanged: { [weak self] targets in
                self?.onTargetsChanged(targets)
                self?.refit(with: targets)
            }
        )
    }
}

extension SettingsWindow: NSWindowDelegate {
    /// Dropped on close so the panes are rebuilt from current values next time,
    /// and so nothing SwiftUI-shaped stays alive behind a closed window.
    /// The user can revoke the login item in System Settings while this window
    /// is open. Coming back to it is the moment to find out.
    func windowDidBecomeKey(_ notification: Notification) {
        loginItem.refresh()
        isFrontmost = true
        refreshContent()
        retimeRefresh()
    }

    /// Coming back to the front is the moment to catch up; going away is the
    /// moment to stop spending anything at all.
    func windowDidResignKey(_ notification: Notification) {
        isFrontmost = false
        retimeRefresh()
    }

    func windowWillClose(_ notification: Notification) {
        isFrontmost = false
        refreshTimer?.invalidate()
        refreshTimer = nil
        window?.delegate = nil
        window = nil
        hosting = nil
    }
}
