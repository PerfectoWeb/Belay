import AppKit
import SwiftUI
import XCTest

@testable import Vigil

/// Covers the panel's lifecycle, not its visibility.
///
/// `NSPopover.show(relativeTo:of:)` needs its positioning view's window to be on
/// a screen, and in this test host `button.window?.screen` is nil and
/// `NSApp.isActive` is false — the status bar window is never attached to a
/// display. `isShown` therefore cannot become true here however long the run
/// loop spins, and asserting on it would only produce a test that fails for a
/// reason unrelated to the code. Actually seeing the panel is a manual step in
/// `docs/QA-CHECKLIST.md`.
///
/// What *is* verifiable here is the part with a measurable cost if it
/// regresses: that closing the panel drops the SwiftUI view rather than leaving
/// it alive and re-rendering behind a closed popover (docs/08).
@MainActor
final class PanelControllerTests: XCTestCase {
    private var statusItem: NSStatusItem?

    override func setUp() async throws {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    }

    override func tearDown() async throws {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    func testShowBuildsTheHostedViewAndHideDropsIt() throws {
        let button = try XCTUnwrap(statusItem?.button)
        let panel = PanelController(state: AppState())

        XCTAssertNil(panel.hostedControllerForTesting)

        panel.show(relativeTo: button)
        XCTAssertNotNil(panel.hostedControllerForTesting, "show did not build the panel")

        panel.hide()
        XCTAssertNil(panel.hostedControllerForTesting, "the hosting controller survived a close")
    }

    func testHideIsSafeWhenNothingIsShowing() {
        let panel = PanelController(state: AppState())
        panel.hide()
        panel.hide()
        XCTAssertNil(panel.hostedControllerForTesting)
    }

    /// A zero-height content view is
    /// the failure mode that would present an empty popover.
    ///
    /// SwiftUI drives the size through `preferredContentSize`, so that is what
    /// this reads, falling back to the popover for the moment before AppKit has
    /// copied it across.
    func testTheOpenPanelHasASensibleContentSize() throws {
        let button = try XCTUnwrap(statusItem?.button)
        let panel = PanelController(state: AppState())
        panel.show(relativeTo: button)

        let size = try XCTUnwrap(panel.contentSizeForTesting)
        XCTAssertEqual(size.width, PanelView.width, accuracy: 1)
        XCTAssertGreaterThan(size.height, 40, "the panel would open empty")

        panel.hide()
    }
}

/// The disclosure judder, as a test.
///
/// Nothing in the panel may animate its own layout: SwiftUI easing a height
/// while `NSPopover` resizes to follow it, one frame behind, is what made the
/// header — and later the whole container — shake when a disclosure opened
/// below it. The controller sets the size in one step, and this fails if a
/// `.animation(…)` modifier reappears anywhere in the panel's layout.
@MainActor
final class PanelAnimationTests: XCTestCase {
    /// The sentence a panel file has to carry before it is allowed to animate.
    static let exemption = "// Animates nothing that can change the panel's height."

    func testNothingInThePanelAnimatesItsOwnLayout() throws {
        let panel = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/VigilApp/Panel")
        let files = try FileManager.default.contentsOfDirectory(at: panel, includingPropertiesForKeys: nil)

        var exempt = 0
        for file in files where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            // A file may animate only if it says, in itself, that what it
            // animates cannot move anything. Keeping the reason next to the code
            // rather than in a list here is what stops the list growing by
            // habit: adding an exemption has to be a deliberate sentence.
            if source.contains(Self.exemption) {
                exempt += 1
                continue
            }
            XCTAssertFalse(
                source.contains(".animation("),
                "\(file.lastPathComponent) animates layout — the popover will judder")
            XCTAssertFalse(
                source.contains("withAnimation"),
                "\(file.lastPathComponent) animates layout — the popover will judder")
        }
        XCTAssertGreaterThan(exempt, 0, "the exemption marker no longer matches anything")
    }

    /// SwiftUI owns the size, through `preferredContentSize`.
    ///
    /// This assertion used to be the exact opposite. The controller measured the
    /// content itself and pushed the result in, which avoided the judder and
    /// worked until macOS 15, where the seed and the measurement disagreed and
    /// the panel opened too short to hold its own contents. The judder is now
    /// prevented at its source by the scan above rather than by taking the size
    /// away from the framework that computes it.
    func testSwiftUIDrivesThePopoverSize() throws {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let button = try XCTUnwrap(item.button)
        let panel = PanelController(state: AppState())
        panel.show(relativeTo: button)
        let hosting = try XCTUnwrap(panel.hostedControllerForTesting as? NSHostingController<PanelView>)
        XCTAssertTrue(
            hosting.sizingOptions.contains(.preferredContentSize),
            "the panel is measuring itself again, and macOS 15 clipped it when it did")
        panel.hide()
    }
}
