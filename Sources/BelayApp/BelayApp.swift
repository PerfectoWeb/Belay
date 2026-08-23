import BelayProviders
import BelaySettings
import BelaySupport
import SwiftUI
import UserNotifications

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
    var updateTimer: Timer?
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

    var controller: BelayController?
    /// Held for the life of the app: the notification centre keeps its delegate
    /// weakly, and a delegate that has been collected is a banner that opens
    /// nothing when clicked.
    private let notificationClicks = NotificationClicks()
    var statusItem: StatusItemController?
    private var panel: PanelController?
    private var onboarding: OnboardingWindow?
    private var whatsNew: WhatsNewWindow?
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
        wireUpdateRow(statusItem, settingsWindow)
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
        observeUpdateStatus(settingsWindow.updates)
        Log.signposter.endInterval("launch", interval)

        // After the interval: neither of these may count against the
        // cold-launch budget, and on most launches neither of them appears.
        openTheScreensShownOnce(statusItem: statusItem, controller: controller)
    }

    /// The status menu's update row: a question until there is an answer.
    ///
    /// Absent in the App Store build, which updates through the store. Where it
    /// is present, the wording is the whole point: "Check for Updates" asks, and
    /// once the checker knows, the row names the version, which is the only
    /// phrasing that says what pressing it will get you without opening a window
    /// first.
    private func wireUpdateRow(_ statusItem: StatusItemController, _ settings: SettingsWindow?) {
        statusItem.updateStatus = { [weak settings] in
            guard ReleaseChecker.isSupported, let checker = settings?.updates else { return nil }
            if case .available(let version, _) = checker.status {
                return (String(localized: "Update Now (v\(version))"), true)
            }
            return (String(localized: "Check for Updates"), false)
        }
        // Whatever the switch was last set to, honoured from launch: a crash
        // on the next start is exactly the one worth having.
        Diagnostics.setEnabled(self.settings.keepLocalReports)

        NotificationClicks.onUpdate = { [weak settings] in
            settings?.show(pane: .general)
        }
        UNUserNotificationCenter.current().delegate = notificationClicks

        statusItem.isUpdateWaiting = { [weak settings] in
            guard ReleaseChecker.isSupported, let checker = settings?.updates else { return false }
            return UpdateWaiting.isWaiting(checker.status)
        }
        statusItem.onUpdate = { [weak settings] in
            guard let checker = settings?.updates else { return }
            // Already know there is one: go straight to installing it. Otherwise
            // this is the question, and the answer belongs where the detail is.
            if case .available = checker.status {
                Feedback.play(.tick)
                if SoftwareUpdate.isSupported { SoftwareUpdate.install() }
            } else {
                checker.check()
                settings?.show(pane: .general)
            }
        }
    }

    /// The welcome screen, then the release notes, in that order and never both.
    ///
    /// A first launch introduces the app; it does not also announce what changed
    /// in the only version that person has ever run. `WhatsNewDecision` says the
    /// same thing from the preference side, and `suppressed` says it from this
    /// one, because the two windows would otherwise land on top of each other in
    /// the middle of the same screen.
    private func openTheScreensShownOnce(
        statusItem: StatusItemController, controller: BelayController
    ) {
        let onboarding = OnboardingWindow(settings: settings)
        onboarding.onStart = { [weak settingsWindow] in settingsWindow?.show(pane: .providers) }
        onboarding.presentIfNeeded(providerReady: true) { [weak controller] in
            controller?.requestProviderAccess(.claudeCode)
        }
        self.onboarding = onboarding

        let whatsNew = WhatsNewWindow(settings: settings)
        whatsNew.presentIfNeeded(suppressed: onboarding.isVisible)
        self.whatsNew = whatsNew

        #if DEBUG
        statusItem.onShowWelcome = { [weak controller] in
            onboarding.presentAgain(providerReady: true) {
                controller?.requestProviderAccess(.claudeCode)
            }
        }
        statusItem.onShowWhatsNew = { whatsNew.present() }
        statusItem.onPretendUpdateChanged = { [weak settingsWindow] in
            settingsWindow?.updates.check()
        }
        #endif
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

}
