import AppKit
import SwiftUI
import VigilProviders
import VigilSettings
import XCTest

@testable import Vigil

/// The Settings button did nothing for a whole build, and nothing said so —
/// SwiftUI's `Settings` scene never produced a window in this `LSUIElement` app,
/// so both the button and Cmd+, were silently inert. These tests exist so that
/// cannot happen again without a red test.
///
/// They deliberately assert on the window and its switcher rather than on the
/// SwiftUI hierarchy: the test host's accessibility tree for a hosted SwiftUI
/// view comes back empty, so anything read from it would prove nothing.
@MainActor
final class SettingsWindowTests: XCTestCase {
    private var defaults: UserDefaults?
    private var suiteName = ""

    override func setUp() async throws {
        suiteName = "com.perfecto-web.vigil.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    private func makeWindow() throws -> SettingsWindow {
        let defaults = try XCTUnwrap(defaults)
        return SettingsWindow(
            settings: SettingsStore(defaults: defaults),
            state: AppState(),
            precise: PreciseDetection(),
            targets: { [] },
            statistics: { UsageStatistics() },
            onTargetsChanged: { _ in }
        )
    }

    func testShowPresentsAWindow() throws {
        let settings = try makeWindow()
        XCTAssertFalse(settings.isVisible)

        settings.show()
        XCTAssertTrue(settings.isVisible, "Settings did not open — the button would do nothing")

        settings.close()
    }

    func testShowingTwiceReusesTheSameWindow() throws {
        let settings = try makeWindow()
        settings.show()
        let first = NSApp.windows.count
        settings.show()
        XCTAssertEqual(NSApp.windows.count, first, "a second Settings window was created")
        settings.close()
    }

    /// The test that was missing. "A window exists" is not "Settings works":
    /// the first version opened a window whose content had no height, so the
    /// switcher collapsed into an overflow chevron and the panes were invisible.
    func testTheWindowIsBigEnoughToShowItsContent() throws {
        let settings = try makeWindow()
        settings.show()
        let window = try XCTUnwrap(settings.window)

        XCTAssertEqual(window.contentView?.frame.width, SettingsPane.width)
        XCTAssertGreaterThanOrEqual(
            window.contentView?.frame.height ?? 0, 160,
            "the Settings window has no usable height — the panes cannot be seen"
        )
        settings.close()
    }

    /// The toolbar is the switcher, and it is the only way to reach a pane. If
    /// an item goes missing, or a pane stops being selectable, that pane becomes
    /// unreachable and the window still looks fine.
    func testTheSwitcherIsInstalledAndCarriesEveryPane() throws {
        let settings = try makeWindow()
        settings.show()
        let window = try XCTUnwrap(settings.window)
        let toolbar = try XCTUnwrap(window.toolbar)
        let expected = SettingsPane.allCases.map(\.itemIdentifier)

        XCTAssertEqual(toolbar.items.map(\.itemIdentifier), expected)
        XCTAssertEqual(settings.toolbarSelectableItemIdentifiers(toolbar), expected)
        XCTAssertEqual(toolbar.displayMode, .iconAndLabel)
        for item in toolbar.items {
            XCTAssertNotNil(item.image, "\(item.itemIdentifier) has no icon")
            XCTAssertFalse(item.label.isEmpty, "\(item.itemIdentifier) has no label")
        }
        settings.close()
    }

    /// The preference style is what centres the title over the items and puts
    /// the hairline under the whole titlebar rather than between the title and
    /// the icons. Drawing the switcher by hand cost both, and neither failed
    /// anything: the window still opened, still worked, and looked wrong.
    func testTheWindowWearsThePreferenceChrome() throws {
        let settings = try makeWindow()
        settings.show()
        let window = try XCTUnwrap(settings.window)

        XCTAssertEqual(window.toolbarStyle, .preference, "the title is no longer centred")
        // Left to macOS on purpose. Overriding it is how the line ends up in a
        // different place from every other preferences window on the Mac.
        XCTAssertEqual(window.titlebarSeparatorStyle, .automatic)
        XCTAssertTrue(
            window.titlebarAccessoryViewControllers.isEmpty,
            "something is bolted into the titlebar again")
        settings.close()
    }

    /// Selecting a pane has to change three things together: the switcher's
    /// selection, the window title, and the window height.
    func testSelectingEachPaneRetitlesAndResizesTheWindow() throws {
        let settings = try makeWindow()
        settings.show()
        let window = try XCTUnwrap(settings.window)

        for pane in SettingsPane.allCases {
            settings.select(pane, animated: false)
            XCTAssertEqual(window.title, pane.title)
            XCTAssertEqual(window.toolbar?.selectedItemIdentifier, pane.itemIdentifier)
            XCTAssertEqual(window.contentView?.frame.width, SettingsPane.width)
            XCTAssertGreaterThanOrEqual(
                window.contentView?.frame.height ?? 0, 160,
                "the \(pane.title) pane left the window with no usable height"
            )
        }
        settings.close()
    }

    /// Every pane has to have real content. A pane that measures near zero is a
    /// pane the user sees as an empty window.
    func testEveryPaneHasContent() throws {
        let defaults = try XCTUnwrap(defaults)
        let store = SettingsStore(defaults: defaults)
        for pane in SettingsPane.allCases {
            let view = SettingsView(
                pane: pane,
                settings: store,
                state: AppState(),
                precise: PreciseDetection(),
                targets: [],
                statistics: UsageStatistics(),
                loginItem: LoginItem(),
                updates: ReleaseChecker(),
                onTargetsChanged: { _ in }
            )
            let hosting = NSHostingView(rootView: view.content)
            hosting.layoutSubtreeIfNeeded()
            let size = hosting.fittingSize
            XCTAssertEqual(size.width, SettingsPane.width, "\(pane.title) is \(size)")
            XCTAssertGreaterThanOrEqual(size.height, 120, "\(pane.title) is \(size)")
        }
    }

    /// A preferences window in the Dock is a preferences window you have lost,
    /// and this one has no document to leave open behind it.
    func testTheWindowCannotBeMinimised() throws {
        let settings = try makeWindow()
        settings.show()
        let window = try XCTUnwrap(settings.window)
        XCTAssertFalse(window.styleMask.contains(.miniaturizable))
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertNil(
            window.standardWindowButton(.miniaturizeButton).map { $0.isEnabled ? "enabled" : nil } ?? nil,
            "the minimise button is still live")
        settings.close()
    }

    func testCloseIsSafeWhenNothingIsOpen() throws {
        let settings = try makeWindow()
        settings.close()
        XCTAssertFalse(settings.isVisible)
    }

    // MARK: - staying current

    private func countingWindow(_ builds: Counter) throws -> SettingsWindow {
        let defaults = try XCTUnwrap(defaults)
        return SettingsWindow(
            settings: SettingsStore(defaults: defaults),
            state: AppState(),
            precise: PreciseDetection(),
            targets: { [] },
            statistics: {
                builds.value += 1
                return UsageStatistics()
            },
            onTargetsChanged: { _ in }
        )
    }

    /// Statistics opened from the menu, then opened again, showed the numbers it
    /// was built with the first time: `show` returned early before rebuilding.
    func testReopeningTheSamePaneRebuildsIt() throws {
        let builds = Counter()
        let settings = try countingWindow(builds)

        settings.show(pane: .statistics)
        let first = builds.value
        XCTAssertGreaterThan(first, 0, "the pane was never built")

        settings.show(pane: .statistics)
        XCTAssertGreaterThan(
            builds.value, first, "re-entering Statistics did not re-read the numbers")
        settings.close()
    }

    /// Coming back to the window is the cheapest moment to catch up, and the one
    /// the user notices.
    func testComingToTheFrontRereadsTheNumbers() throws {
        let builds = Counter()
        let settings = try countingWindow(builds)
        settings.show(pane: .statistics)
        let before = builds.value

        settings.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
        XCTAssertGreaterThan(builds.value, before, "the pane on screen stayed stale")
        settings.close()
    }

    /// The idle budget: nothing ticks unless the pane whose numbers move is both
    /// open and the window the user is looking at.
    func testOnlyAFrontmostStatisticsPanePolls() throws {
        let settings = try makeWindow()
        let key = Notification(name: NSWindow.didBecomeKeyNotification)
        let resigned = Notification(name: NSWindow.didResignKeyNotification)

        // Driven through the delegate rather than by activating the app: this
        // test host is never frontmost, so a real key change would never arrive.
        settings.show(pane: .statistics)
        settings.windowDidResignKey(resigned)
        XCTAssertFalse(settings.isRefreshingForTesting, "polling while another app is in front")

        settings.windowDidBecomeKey(key)
        XCTAssertTrue(settings.isRefreshingForTesting, "an open Statistics pane never updates")

        settings.windowDidResignKey(resigned)
        XCTAssertFalse(settings.isRefreshingForTesting, "it kept polling behind another app")

        settings.windowDidBecomeKey(key)
        settings.select(.general, animated: false)
        XCTAssertFalse(settings.isRefreshingForTesting, "a pane with nothing moving is polling")

        settings.select(.statistics, animated: false)
        XCTAssertTrue(settings.isRefreshingForTesting)

        settings.close()
        XCTAssertFalse(settings.isRefreshingForTesting, "the timer outlived the window")
    }
}

/// Somewhere for a closure under test to count into.
private final class Counter {
    var value = 0
}
