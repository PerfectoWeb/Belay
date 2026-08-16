import AppKit
import BelayCore
import XCTest

@testable import Belay

/// Regression tests for the bug that made the menu bar icon disappear.
///
/// The Off state used the SF Symbol `moon.slash`, which does not exist on
/// macOS 26. `NSImage(systemSymbolName:)` returned nil, the status button got no
/// image, and the item silently vanished — the app was running and completely
/// invisible. The mark is drawn now, so it cannot go missing, and these tests
/// hold that line for every state.
@MainActor
final class BelayGlyphTests: XCTestCase {
    private let everyState: [BelayState] = [
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
            let image = BelayGlyph.statusItemImage(BelayGlyph.Look(state: state))
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
        let off = pixels(BelayGlyph.statusItemImage(.off))
        let watching = pixels(BelayGlyph.statusItemImage(.working))
        XCTAssertNotEqual(off, watching)
    }

    /// Compares whole animation cycles, not single frames. A one-frame check
    /// let `calling` and `alwaysOn` look identical at rest and still pass.
    func testEveryLookIsDistinct() {
        let looks: [BelayGlyph.Look] = [.alwaysOn, .working, .resting, .calling, .off, .blocked]
        var seen: [[Data]: BelayGlyph.Look] = [:]
        for look in looks {
            let cycle = (0..<BelayGlyph.frameCount).map {
                pixels(BelayGlyph.statusItemImage(look, frame: $0))
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
        let calling = (0..<BelayGlyph.frameCount).map {
            pixels(BelayGlyph.statusItemImage(.calling, frame: $0))
        }
        let alwaysOn = pixels(BelayGlyph.statusItemImage(.alwaysOn))
        XCTAssertFalse(
            calling.allSatisfy { $0 == alwaysOn },
            "the awaiting-user look is indistinguishable from always-on"
        )
    }

    func testScalesWithoutLosingTheDrawing() {
        for size in [16.0, 18.0, 32.0, 128.0, 512.0] {
            let image = BelayGlyph.image(.working, frame: 0, size: size)
            XCTAssertFalse(isBlank(image), "the mark is blank at \(size) pt")
        }
    }

    /// The twinkle has to actually change between frames, and only the working
    /// look may animate — every other state must be a still image, or the menu
    /// bar would be moving while nothing is happening.
    func testOnlyWorkingAnimates() {
        let frames = (0..<BelayGlyph.frameCount).map {
            pixels(BelayGlyph.statusItemImage(.working, frame: $0))
        }
        XCTAssertGreaterThan(Set(frames).count, 1, "the working look never changes between frames")

        for look in [BelayGlyph.Look.alwaysOn, .resting, .off, .blocked] {
            XCTAssertFalse(look.isAnimated, "\(look) animates but nothing is happening")
        }
        for look in [BelayGlyph.Look.working, .calling] {
            XCTAssertTrue(look.isAnimated, "\(look) should animate")
        }
    }

    /// The rule the user asked for, pinned: the small sparkles only move when a
    /// session is genuinely working. Always-on is a chosen mode, and cooling
    /// down means the agents have already stopped.
    func testOnlyRealWorkMakesTheSparklesMove() {
        XCTAssertTrue(BelayGlyph.Look(state: .working).isAnimated)
        XCTAssertFalse(BelayGlyph.Look(state: .alwaysOn).isAnimated)
        XCTAssertFalse(BelayGlyph.Look(state: .coolingDown).isAnimated)
        XCTAssertFalse(BelayGlyph.Look(state: .armed).isAnimated)
        XCTAssertEqual(BelayGlyph.Look(state: .coolingDown), .resting)
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

    /// Writes the mark to PNGs so it can be looked at, the way
    /// `SceneFramesTests` does for the welcome scene. Skipped unless
    /// `BELAY_GLYPHS` names a directory.
    ///
    /// The menu bar draws this at 17 points and nothing else, so that is the
    /// size a judgement has to be made at; the large one is only there to see
    /// what the small one is made of.
    func testWriteGlyphs() throws {
        guard let folder = ProcessInfo.processInfo.environment["BELAY_GLYPHS"] else {
            throw XCTSkip("set BELAY_GLYPHS to a directory to write the marks")
        }
        let out = URL(fileURLWithPath: folder)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for look in [BelayGlyph.Look.blocked, .alwaysOn, .off] {
            for size in [CGFloat(17), 96] {
                let image = BelayGlyph.image(look, size: size)
                guard let tiff = image.tiffRepresentation,
                    let rep = NSBitmapImageRep(data: tiff),
                    let png = rep.representation(using: .png, properties: [:])
                else { continue }
                try png.write(
                    to: out.appendingPathComponent("\(look)-\(Int(size)).png"))
            }
        }
    }
}
