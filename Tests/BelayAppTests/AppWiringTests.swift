import AppKit
import BelayCore
import BelaySettings
import XCTest

@testable import Belay

/// The closures that let the panel open Settings.
///
/// They used to capture the window and the panel strongly, and both of those
/// hold `AppState`, which holds the closures — so `applicationWillTerminate`
/// setting its references to nil deallocated nothing and `PanelController.deinit`
/// never ran. Nothing was visibly broken, which is exactly why it survived: the
/// only symptom is a popover's SwiftUI view still observing state after quit.
@MainActor
final class AppWiringTests: XCTestCase {
    private var defaults: UserDefaults?
    private var suiteName = ""

    override func setUp() async throws {
        suiteName = "com.perfectoweb.belay.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    private func makeSettingsWindow(_ state: AppState) throws -> SettingsWindow {
        let defaults = try XCTUnwrap(defaults)
        return SettingsWindow(
            settings: SettingsStore(defaults: defaults),
            state: state,
            precise: PreciseDetection(),
            targets: { [] },
            statistics: { UsageStatistics() },
            onTargetsChanged: { _ in }
        )
    }

    func testWiringDoesNotKeepThePanelOrTheWindowAlive() throws {
        let state = AppState()
        weak var panel: PanelController?
        weak var settings: SettingsWindow?

        try autoreleasepool {
            let strongPanel = PanelController(state: state)
            let strongSettings = try makeSettingsWindow(state)
            panel = strongPanel
            settings = strongSettings
            state.connect(settings: strongSettings, panel: strongPanel) { _ in }
            XCTAssertNotNil(panel)
        }

        XCTAssertNil(panel, "AppState still holds the panel — PanelController.deinit never runs")
        XCTAssertNil(settings, "AppState still holds the Settings window")
    }

    /// Weak captures must not turn the buttons into no-ops while everything is
    /// alive, which is the obvious way to over-correct this.
    func testTheWiredClosuresStillDoTheirJob() throws {
        let state = AppState()
        let panel = PanelController(state: state)
        let settings = try makeSettingsWindow(state)
        var granted: [ProviderID] = []
        state.connect(settings: settings, panel: panel) { granted.append($0) }

        state.onOpenSettings()
        XCTAssertTrue(settings.isVisible, "the Settings button stopped opening Settings")

        state.onGrantAccess(.claudeCode)
        XCTAssertEqual(granted, [.claudeCode])
        XCTAssertEqual(settings.pane, .providers, "Fix did not land on the Providers pane")
        settings.close()
    }
}
