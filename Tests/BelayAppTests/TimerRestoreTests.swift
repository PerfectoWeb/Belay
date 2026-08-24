import BelayCore
import BelaySettings
import XCTest

@testable import Belay

/// The controller half of timer persistence: what was stored comes back into
/// the coordinator, and a stale record is cleaned up rather than resurrected.
@MainActor
final class TimerRestoreTests: XCTestCase {
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

    func testStoredTimerReachesTheCoordinator() async throws {
        let settings = SettingsStore(defaults: try XCTUnwrap(defaults))
        settings.mode = .alwaysOn
        let deadline = Date().addingTimeInterval(1800)
        settings.alwaysOnTimer = (3600, deadline)

        let controller = BelayController(settings: settings, state: AppState())
        controller.restoreAlwaysOnTimer()
        try await Task.sleep(nanoseconds: 200_000_000)

        let timer = await controller.coordinator.snapshot.timer
        XCTAssertEqual(timer?.duration, 3600)
        XCTAssertEqual(timer?.deadline.timeIntervalSince(deadline) ?? 1, 0, accuracy: 0.001)
    }

    func testStaleRecordIsClearedWhenTheModeMovedOn() throws {
        let settings = SettingsStore(defaults: try XCTUnwrap(defaults))
        settings.mode = .auto
        settings.alwaysOnTimer = (3600, Date().addingTimeInterval(1800))

        let controller = BelayController(settings: settings, state: AppState())
        controller.restoreAlwaysOnTimer()
        XCTAssertNil(settings.alwaysOnTimer, "a record the mode outgrew must not survive")
    }

    func testSettingATimerPersistsAndClearingForgets() throws {
        let settings = SettingsStore(defaults: try XCTUnwrap(defaults))
        settings.mode = .alwaysOn
        let controller = BelayController(settings: settings, state: AppState())

        controller.setAlwaysOnTimer(900)
        let stored = try XCTUnwrap(settings.alwaysOnTimer)
        XCTAssertEqual(stored.duration, 900)
        XCTAssertEqual(stored.deadline.timeIntervalSinceNow, 900, accuracy: 5)

        controller.setMode(.auto)
        XCTAssertNil(settings.alwaysOnTimer)
    }
}
