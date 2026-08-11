import AppKit
import SwiftUI
import VigilSettings
import XCTest

@testable import Vigil

/// The Settings button did nothing for a whole build, and nothing said so —
/// SwiftUI's `Settings` scene never produced a window in this `LSUIElement` app,
/// so both the button and Cmd+, were silently inert. These tests exist so that
/// cannot happen again without a red test.
///
/// They deliberately assert on the window and its toolbar rather than on the
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

    /// The toolbar is the switcher. If an item goes missing, or a pane stops
    /// being selectable, the pane becomes unreachable.
    func testToolbarCarriesEveryPane() throws {
        let settings = try makeWindow()
        settings.show()
        let toolbar = try XCTUnwrap(settings.window?.toolbar)
        let expected = SettingsPane.allCases.map(\.itemIdentifier)

        XCTAssertEqual(toolbar.items.map(\.itemIdentifier), expected)
        XCTAssertEqual(settings.toolbarSelectableItemIdentifiers(toolbar), expected)
        XCTAssertEqual(toolbar.displayMode, .iconAndLabel)
        XCTAssertEqual(settings.window?.toolbarStyle, .preference)
        for item in toolbar.items {
            XCTAssertNotNil(item.image, "\(item.itemIdentifier) has no icon")
            XCTAssertFalse(item.label.isEmpty, "\(item.itemIdentifier) has no label")
        }
        settings.close()
    }

    /// Selecting a pane has to change three things together: the toolbar
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
}
