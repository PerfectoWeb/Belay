import BelayProviders
import BelaySettings
import BelaySupport
import SwiftUI

@main
struct BelayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            // A SwiftUI App needs at least one Scene, but this one is never
            // shown: LSUIElement leaves nothing responding to
            // showSettingsWindow:, so SettingsWindow owns the real window.
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var updateTimer: Timer?
    /// Built eagerly so the Settings scene has something to bind to before
    /// `applicationDidFinishLaunching` runs. Reading preferences touches no
    /// hardware and costs nothing.
    let settings: SettingsStore = {
        // Before anything reads preferences, and before the schema migration
        // inside SettingsStore runs on them. See PreviousDomain.
        PreviousDomain.adopt()
        return SettingsStore()
    }()
    let appState: AppState
    let precise = PreciseDetection()

    override init() {
        appState = AppState()
        super.init()
    }

    private var controller: BelayController?
    private var statusItem: StatusItemController?
    private var panel: PanelController?
    private var onboarding: OnboardingWindow?
    private var settingsWindow: SettingsWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard SingleInstance.claim() else {
            NSApp.terminate(nil)
            return
        }
        let interval = Log.signposter.beginInterval("launch")
        // Sound is not owned by any one screen — the mode can be changed from
        // the panel and the switch lives in Settings — so the rule is wired
        // once, here, and read wherever something is about to make a noise.
        Feedback.isEnabled = { [weak settings] in settings?.soundEffects ?? true }
        let controller = BelayController(settings: settings, state: appState, precise: precise)
        let panel = PanelController(state: controller.state)
        let statusItem = StatusItemController(state: controller.state, panel: panel)
        controller.state.onChange = { [weak statusItem] in statusItem?.render() }
        let settingsWindow = SettingsWindow(
            settings: settings,
            state: appState,
            precise: precise,
            targets: { [weak controller] in controller?.genericTargets ?? [] },
            statistics: { [weak controller] in controller?.usage.statistics ?? UsageStatistics() },
            onTargetsChanged: { [weak controller] in controller?.updateGenericTargets($0) },
            onResetStatistics: { [weak controller] in controller?.usage.reset() }
        )
        statusItem.onOpenPane = { [weak settingsWindow] in settingsWindow?.show(pane: $0) }
        // The panel's "Fix" button. Every notice it can show is resolved on the
        // Providers pane — Claude Code needs folder access, the generic provider
        // needs a folder or a preset — so it opens there and asks the controller
        // for whatever the build needs, rather than doing nothing at all, which
        // is what it did.
        appState.connect(settings: settingsWindow, panel: panel) { [weak controller] provider in
            controller?.requestProviderAccess(provider)
        }
        self.settingsWindow = settingsWindow

        controller.start()
        self.controller = controller
        self.statusItem = statusItem
        self.panel = panel
        // The mode is here because a clean-machine QA run has no other way to
        // learn which preferences domain the app actually read. Writing the
        // plist and then reading it back proves only what the script wrote.
        Log.app.notice(
            """
            Belay \(Branding.version, privacy: .public) launched, \
            mode \(self.settings.mode.rawValue, privacy: .public)
            """)
        scheduleUpdateChecks(settingsWindow.updates)
        Log.signposter.endInterval("launch", interval)

        // After the interval: onboarding must not count against the cold-launch
        // budget, and it only appears on a first run anyway.
        let onboarding = OnboardingWindow(settings: settings)
        onboarding.presentIfNeeded(providerReady: true) { [weak controller] in
            controller?.requestProviderAccess(.claudeCode)
        }
        self.onboarding = onboarding
    }

    func applicationWillTerminate(_ notification: Notification) {
        updateTimer?.invalidate()
        updateTimer = nil
        settingsWindow?.close()
        settingsWindow = nil
        controller?.shutdown()
        panel?.hide()
        controller = nil
        statusItem = nil
        panel = nil
    }

    var controllerTargets: [GenericTarget] { controller?.genericTargets ?? [] }

    func updateGenericTargets(_ targets: [GenericTarget]) {
        controller?.updateGenericTargets(targets)
    }

    /// Launching Belay again opens Settings.
    ///
    /// A menu bar app with no Dock icon has exactly one way in — the status
    /// item — and macOS hides status items when the menu bar is full. On a
    /// crowded menu bar that leaves no way to reach Settings at all. Re-opening
    /// the app is the standard escape hatch, and it costs one method.
    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows: Bool) -> Bool {
        settingsWindow?.show()
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// Daily, and once shortly after launch.
    ///
    /// The post-launch one waits for onboarding to have been through at least
    /// once. Checks are on by default now, and without this the very first
    /// launch opened a socket eight seconds in, while the welcome screen was
    /// still on the display saying nothing leaves this Mac. Both statements were
    /// true separately and the pair of them was not.
    private func scheduleUpdateChecks(_ checker: ReleaseChecker) {
        let timer = Timer(timeInterval: 3600, repeats: true) { _ in
            MainActor.assumeIsolated { checker.checkIfDue() }
        }
        timer.tolerance = 600
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
        // After launch, not during it: nothing about an update belongs in the
        // cold-start path.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard self?.settings.hasCompletedOnboarding == true else { return }
            checker.checkIfDue()
        }
    }

}
