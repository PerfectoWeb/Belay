import AppKit
import XCTest

@testable import Belay

/// The right-click menu. Small enough that every item earns its place, which is
/// why it is worth a test: an item that stops opening anything is invisible
/// until somebody clicks it.
@MainActor
final class StatusMenuTests: XCTestCase {
    /// Held for the lifetime of the test: `NSMenuItem.target` is weak, so a
    /// controller created and dropped inside a helper takes every target with it
    /// and the menu reads as inert when it is not.
    private var controller: StatusItemController!

    override func setUp() async throws {
        let state = AppState()
        controller = StatusItemController(state: state, panel: PanelController(state: state))
    }

    override func tearDown() async throws {
        controller = nil
    }

    func testTheMenuIsTheFourThingsItShouldBe() throws {
        let menu = controller.menuForTesting
        let titles = menu.items.map(\.title)
        // Compared against the localised strings, not English literals: the
        // suite has to pass on a Mac that is not running in English.
        XCTAssertEqual(
            titles,
            [
                String(localized: "Statistics"),
                String(localized: "Settings…"),
                String(localized: "About \(Branding.appName)"),
                "",
                String(localized: "Quit")
            ],
            "the separator is the empty title")
    }

    /// An ellipsis promises a dialog that asks for something first. Statistics
    /// and About just show a pane. Settings keeps its dots because every other
    /// macOS app spells it that way.
    func testOnlySettingsCarriesAnEllipsis() {
        let menu = controller.menuForTesting
        let withDots = menu.items.filter { $0.title.hasSuffix("…") }.map(\.title)
        XCTAssertEqual(withDots, [String(localized: "Settings…")])
    }

    func testEveryCommandHasAnIcon() {
        for item in controller.menuForTesting.items where !item.isSeparatorItem {
            XCTAssertNotNil(item.image, "\(item.title) has no icon")
        }
    }

    func testEveryCommandActuallyDoesSomething() {
        for item in controller.menuForTesting.items where !item.isSeparatorItem {
            XCTAssertNotNil(item.action, "\(item.title) is inert")
            XCTAssertNotNil(item.target, "\(item.title) has no target")
        }
    }

    /// The three pane commands have to reach three different panes.
    func testTheMenuOpensThreeDistinctDestinations() {
        var opened: [SettingsPane] = []
        controller.onOpenPane = { opened.append($0) }

        for item in controller.menuForTesting.items where !item.isSeparatorItem {
            guard item.title != String(localized: "Quit"), let action = item.action else { continue }
            // Through the ObjC runtime, the same way AppKit dispatches it — the
            // point is that the wiring works, not that the method exists.
            _ = (controller as AnyObject).perform(action)
        }

        XCTAssertEqual(opened, [.statistics, .general, .about])
    }
}
