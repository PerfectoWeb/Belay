import SwiftUI
import VigilProviders
import VigilSettings
import VigilSupport

@main
struct VigilApp: App {
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
    let settings = SettingsStore()
    let appState: AppState
    let precise = PreciseDetection()

    override init() {
        appState = AppState()
        super.init()
    }

    private var controller: VigilController?
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
        let controller = VigilController(settings: settings, state: appState, precise: precise)
        let panel = PanelController(state: controller.state)
        let statusItem = StatusItemController(state: controller.state, panel: panel)
        controller.state.onChange = { [weak statusItem] in statusItem?.render() }
        let settingsWindow = SettingsWindow(
            settings: settings,
            state: appState,
            precise: precise,
            targets: { [weak controller] in controller?.genericTargets ?? [] },
            statistics: { [weak controller] in controller?.usage.statistics ?? UsageStatistics() },
            onTargetsChanged: { [weak controller] in controller?.updateGenericTargets($0) }
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
        Log.app.notice("Vigil \(Branding.version, privacy: .public) launched")
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

    /// Launching Vigil again opens Settings.
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

    /// Daily, and once shortly after launch. Both are no-ops until the user
    /// turns update checks on, so an app nobody asked to check never opens a
    /// socket — see `ReleaseChecker`.
    private func scheduleUpdateChecks(_ checker: ReleaseChecker) {
        let timer = Timer(timeInterval: 3600, repeats: true) { _ in
            MainActor.assumeIsolated { checker.checkIfDue() }
        }
        timer.tolerance = 600
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer
        // After launch, not during it: nothing about an update belongs in the
        // cold-start path.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { checker.checkIfDue() }
    }

}
