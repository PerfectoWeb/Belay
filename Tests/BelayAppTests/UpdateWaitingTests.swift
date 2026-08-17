import AppKit
import BelayCore
import XCTest

@testable import Belay

/// The update mark, and the rule that keeps it out of the way.
///
/// The whole point of this feature is restraint: an app whose job is to protect a
/// long agent run must not grow a new mark in the middle of one. That rule is
/// worth a test of its own, because it is the part a later change would break
/// without noticing.
@MainActor
final class UpdateWaitingTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "belay.tests.updatewaiting")!
        defaults.removePersistentDomain(forName: "belay.tests.updatewaiting")
    }

    private let available = ReleaseChecker.Status.available(
        version: "1.2.1", url: URL(string: "https://example.invalid/x.dmg")!)

    // MARK: - Whether the app should be saying anything

    func testNothingWaitingWhenUpToDate() {
        XCTAssertFalse(UpdateWaiting.isWaiting(.upToDate(Date()), defaults: defaults))
        XCTAssertFalse(UpdateWaiting.isWaiting(.never, defaults: defaults))
        XCTAssertFalse(UpdateWaiting.isWaiting(.checking, defaults: defaults))
        XCTAssertFalse(UpdateWaiting.isWaiting(.noneYet, defaults: defaults))
        XCTAssertFalse(UpdateWaiting.isWaiting(.failed("offline"), defaults: defaults))
    }

    func testWaitingWhenAvailableAndNotSkipped() {
        XCTAssertTrue(UpdateWaiting.isWaiting(available, defaults: defaults))
    }

    func testSkippingSilencesThatVersionOnly() {
        UpdateWaiting.skip("1.2.1", defaults: defaults)
        XCTAssertFalse(UpdateWaiting.isWaiting(available, defaults: defaults))

        let next = ReleaseChecker.Status.available(
            version: "1.2.2", url: URL(string: "https://example.invalid/y.dmg")!)
        XCTAssertTrue(
            UpdateWaiting.isWaiting(next, defaults: defaults),
            "skipping one version must not silence the next one")
    }

    func testClearingBringsItBack() {
        UpdateWaiting.skip("1.2.1", defaults: defaults)
        UpdateWaiting.clear(defaults: defaults)
        XCTAssertTrue(UpdateWaiting.isWaiting(available, defaults: defaults))
    }

    // MARK: - The drawing

    func testTheDotChangesTheMark() {
        for look in [BelayGlyph.Look.resting, .alwaysOn, .off, .blocked] {
            XCTAssertNotEqual(
                pixels(BelayGlyph.statusItemImage(look, waiting: false)),
                pixels(BelayGlyph.statusItemImage(look, waiting: true)),
                "\(look) draws the same with and without an update waiting")
        }
    }

    func testNoDotWhileAnAgentIsWorkingOrWaitingOnTheUser() {
        for look in [BelayGlyph.Look.working, .calling] {
            for frame in 0..<BelayGlyph.frameCount {
                XCTAssertEqual(
                    pixels(BelayGlyph.statusItemImage(look, frame: frame, waiting: false)),
                    pixels(BelayGlyph.statusItemImage(look, frame: frame, waiting: true)),
                    "\(look) frame \(frame) grew an update mark mid-run")
            }
        }
    }

    func testTheDotIsInTheCornerTheArtworkLeavesEmpty() {
        let plain = pixels(BelayGlyph.image(.resting, size: 48, waiting: false))
        let dotted = pixels(BelayGlyph.image(.resting, size: 48, waiting: true))
        // Bottom left in image coordinates, which start at the top.
        let changedLow = zip(plain, dotted).enumerated().filter { $0.element.0 != $0.element.1 }
        XCTAssertFalse(changedLow.isEmpty, "nothing changed at all")
        let width = 48
        let inLowerLeft = changedLow.allSatisfy { index, _ in
            let pixel = index / 4
            return pixel % width < width / 2 && pixel / width > width / 2
        }
        XCTAssertTrue(inLowerLeft, "the dot moved out of the lower left corner")
    }

    func testTheMarkStaysATemplate() {
        XCTAssertTrue(BelayGlyph.statusItemImage(.resting, waiting: true).isTemplate)
    }

    private func pixels(_ image: NSImage) -> [UInt8] {
        guard let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let data = rep.bitmapData
        else { return [] }
        return Array(UnsafeBufferPointer(start: data, count: rep.bytesPerRow * rep.pixelsHigh))
    }
}
