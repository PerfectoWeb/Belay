import AppKit
import BelayCore
import BelaySettings
import XCTest

@testable import Belay

/// The switch's whole chain below the tap: `onToggleProvider` must land in the
/// persisted settings. The tap itself is SwiftUI's; everything after it is
/// ours, and a Cline toggle once appeared to vanish (2026-08-24 — traced to a
/// cfprefsd flush race during rapid relaunches, but the chain deserved a
/// regression test either way).
@MainActor
final class ProviderToggleTests: XCTestCase {
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

    func testToggleLandsInPersistedSettings() async throws {
        let defaults = try XCTUnwrap(defaults)
        let settings = SettingsStore(defaults: defaults)
        settings.builtInsDetected = true
        settings.enabledProviders = [.claudeCode, .codex]
        let controller = BelayController(settings: settings, state: AppState())
        controller.state.onToggleProvider = { [weak controller] provider, on in
            controller?.setProviderEnabled(provider, on)
        }

        controller.state.onToggleProvider(.cline, true)
        XCTAssertTrue(settings.enabledProviders.contains(.cline))
        // And the write went through the store, not just the in-memory copy.
        let fresh = SettingsStore(defaults: defaults)
        XCTAssertTrue(fresh.enabledProviders.contains(.cline))

        controller.state.onToggleProvider(.cline, false)
        XCTAssertFalse(settings.enabledProviders.contains(.cline))
        XCTAssertFalse(SettingsStore(defaults: defaults).enabledProviders.contains(.cline))
    }
}
