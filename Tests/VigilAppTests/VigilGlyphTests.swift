import AppKit
import VigilCore
import XCTest

@testable import Vigil

/// Regression tests for the bug that made the menu bar icon disappear.
///
/// The Off state used the SF Symbol `moon.slash`, which does not exist on
/// macOS 26. `NSImage(systemSymbolName:)` returned nil, the status button got no
/// image, and the item silently vanished — the app was running and completely
/// invisible. The mark is drawn now, so it cannot go missing, and these tests
/// hold that line for every state.
@MainActor
final class VigilGlyphTests: XCTestCase {
    private let everyState: [VigilState] = [
        .off,
        .alwaysOn,
        .armed,
        .working,
        .awaitingUser,
        .coolingDown,
        .suspended(.batteryLow(charge: 0.1)),
        .suspended(.maxDurationReached(3600))
    ]

    func testEveryStateProducesAVisibleImage() {
        for state in everyState {
            let image = VigilGlyph.statusItemImage(VigilGlyph.Look(state: state))
            XCTAssertGreaterThan(image.size.width, 0, "\(state) has a zero-width image")
            XCTAssertGreaterThan(image.size.height, 0, "\(state) has a zero-height image")
            XCTAssertTrue(image.isTemplate, "\(state) is not a template image")
            XCTAssertFalse(
                isBlank(image),
                "\(state) draws nothing — this is exactly how the icon vanished before"
            )
        }
    }

    func testOffLooksDifferentFromWorking() {
        // If these two ever render identically, the user cannot tell whether
        // their Mac is being held awake, which is the whole point of the icon.
        let off = pixels(VigilGlyph.statusItemImage(.off))
        let watching = pixels(VigilGlyph.statusItemImage(.working))
        XCTAssertNotEqual(off, watching)
    }

    /// Compares whole animation cycles, not single frames. A one-frame check
    /// let `calling` and `alwaysOn` look identical at rest and still pass.
    func testEveryLookIsDistinct() {
        let looks: [VigilGlyph.Look] = [.alwaysOn, .working, .resting, .calling, .off, .blocked]
        var seen: [[Data]: VigilGlyph.Look] = [:]
        for look in looks {
            let cycle = (0..<VigilGlyph.frameCount).map {
                pixels(VigilGlyph.statusItemImage(look, frame: $0))
            }
            if let clash = seen[cycle] {
                XCTFail("\(look) renders exactly like \(clash)")
            }
            seen[cycle] = look
        }
    }

    /// Two states can share a frame, but never every frame — otherwise the user
    /// cannot tell them apart at the moment they happen to look.
    func testCallingIsNeverMistakableForAlwaysOn() {
        let calling = (0..<VigilGlyph.frameCount).map {
            pixels(VigilGlyph.statusItemImage(.calling, frame: $0))
        }
        let alwaysOn = pixels(VigilGlyph.statusItemImage(.alwaysOn))
        XCTAssertFalse(
            calling.allSatisfy { $0 == alwaysOn },
            "the awaiting-user look is indistinguishable from always-on"
        )
    }

    func testScalesWithoutLosingTheDrawing() {
        for size in [16.0, 18.0, 32.0, 128.0, 512.0] {
            let image = VigilGlyph.image(.working, frame: 0, size: size)
            XCTAssertFalse(isBlank(image), "the mark is blank at \(size) pt")
        }
    }

    /// The twinkle has to actually change between frames, and only the working
    /// look may animate — every other state must be a still image, or the menu
    /// bar would be moving while nothing is happening.
    func testOnlyWorkingAnimates() {
        let frames = (0..<VigilGlyph.frameCount).map {
            pixels(VigilGlyph.statusItemImage(.working, frame: $0))
        }
        XCTAssertGreaterThan(Set(frames).count, 1, "the working look never changes between frames")

        for look in [VigilGlyph.Look.alwaysOn, .resting, .off, .blocked] {
            XCTAssertFalse(look.isAnimated, "\(look) animates but nothing is happening")
        }
        for look in [VigilGlyph.Look.working, .calling] {
            XCTAssertTrue(look.isAnimated, "\(look) should animate")
        }
    }

    /// The rule the user asked for, pinned: the small sparkles only move when a
    /// session is genuinely working. Always-on is a chosen mode, and cooling
    /// down means the agents have already stopped.
    func testOnlyRealWorkMakesTheSparklesMove() {
        XCTAssertTrue(VigilGlyph.Look(state: .working).isAnimated)
        XCTAssertFalse(VigilGlyph.Look(state: .alwaysOn).isAnimated)
        XCTAssertFalse(VigilGlyph.Look(state: .coolingDown).isAnimated)
        XCTAssertFalse(VigilGlyph.Look(state: .armed).isAnimated)
        XCTAssertEqual(VigilGlyph.Look(state: .coolingDown), .resting)
    }

    private func pixels(_ image: NSImage) -> Data {
        guard let tiff = image.tiffRepresentation else { return Data() }
        return tiff
    }

    /// A template image is black-on-transparent, so "did anything draw" is
    /// "is any pixel non-transparent".
    private func isBlank(_ image: NSImage) -> Bool {
        guard
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff)
        else { return true }

        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                return false
            }
        }
        return true
    }
}
