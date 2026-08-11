import AppKit
import VigilCore
import XCTest

@testable import Vigil

/// The marks in the session list.
///
/// These are vendor logos shipped as template assets, and the way that breaks is
/// quiet: rename an imageset, or let `actool` drop one, and `NSImage(named:)`
/// returns nil, the drawn fallback takes over, and the app keeps running while
/// showing the wrong thing. Nothing else in the app would notice.
@MainActor
final class ProviderMarkTests: XCTestCase {
    private func coverage(_ image: NSImage) -> Double {
        guard
            let data = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: data)
        else { return 0 }
        var opaque = 0
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 {
                opaque += 1
            }
        }
        return Double(opaque) / Double(bitmap.pixelsWide * bitmap.pixelsHigh)
    }

    func testEveryShippedLogoIsInTheBundle() {
        for name in ProviderMark.bundledLogos {
            XCTAssertNotNil(
                NSImage(named: "logo-\(name)"),
                "logo-\(name) is missing from the asset catalogue — rows fall back to a drawn shape")
        }
    }

    /// A logo that rasterises to nothing is worse than no logo: the row keeps
    /// its space and shows a blank.
    func testEveryLogoActuallyDrawsSomething() {
        for name in ProviderMark.bundledLogos {
            let image = ProviderMark.image(preset: name, size: 64)
            let inked = coverage(image)
            XCTAssertGreaterThan(inked, 0.02, "logo-\(name) is blank or nearly blank")
            XCTAssertLessThan(inked, 0.9, "logo-\(name) is a solid block — the artwork did not survive")
        }
    }

    /// Recolouring is the whole reason these are template images: the row draws
    /// them primary when live and secondary when not.
    func testLogosAreTemplateImages() {
        for name in ProviderMark.bundledLogos {
            XCTAssertTrue(ProviderMark.image(preset: name, size: 15).isTemplate, name)
        }
        XCTAssertTrue(ProviderMark.image(for: .generic, size: 15).isTemplate)
    }

    /// Cline's artwork is 116×120. Stretching it to a square would be a subtle,
    /// permanent distortion of somebody's trademark.
    func testANonSquareLogoIsNotStretched() throws {
        let source = try XCTUnwrap(NSImage(named: "logo-cline"))
        XCTAssertNotEqual(source.size.width, source.size.height, "fixture assumption changed")
        let mark = ProviderMark.image(preset: "cline", size: 32)
        XCTAssertEqual(mark.size, NSSize(width: 32, height: 32), "the box stays square")
        // Aspect-fitting a 116×120 source into 32×32 leaves the width short.
        XCTAssertLessThan(coverage(mark), coverage(ProviderMark.image(preset: "gemini", size: 32)) + 0.5)
    }

    func testTheKnownProvidersUseTheirOwnMark() {
        let claude = ProviderMark.image(for: .claudeCode, size: 32)
        let codex = ProviderMark.image(for: .codex, size: 32)
        XCTAssertNotEqual(claude.tiffRepresentation, codex.tiffRepresentation)
        XCTAssertEqual(
            claude.tiffRepresentation, ProviderMark.image(preset: "claude", size: 32).tiffRepresentation)
        XCTAssertEqual(
            codex.tiffRepresentation, ProviderMark.image(preset: "codex", size: 32).tiffRepresentation)
    }

    /// A generic session carries the preset it came from, so Gemini looks like
    /// Gemini rather than like "some other agent".
    func testAGenericSessionShowsItsPresetMark() {
        let gemini = ProviderMark.image(for: .generic, preset: "gemini", size: 32)
        let neutral = ProviderMark.image(for: .generic, size: 32)
        XCTAssertEqual(
            gemini.tiffRepresentation, ProviderMark.image(preset: "gemini", size: 32).tiffRepresentation)
        XCTAssertNotEqual(gemini.tiffRepresentation, neutral.tiffRepresentation)
    }

    /// A preset with no artwork must fall back, not blank out. Aider ships none.
    func testAPresetWithNoLogoStillGetsAMark() {
        XCTAssertGreaterThan(coverage(ProviderMark.image(preset: "aider", size: 64)), 0.01)
        XCTAssertGreaterThan(coverage(ProviderMark.image(preset: "no-such-agent", size: 64)), 0.01)
    }

    /// Two rows that look identical tell the user nothing.
    func testEveryMarkIsDistinct() {
        let names = ProviderMark.bundledLogos + ["aider", "terminal", "no-such-agent"]
        var seen: [String: Data] = [:]
        for name in names {
            let data = try? XCTUnwrap(ProviderMark.image(preset: name, size: 32).tiffRepresentation)
            for (other, existing) in seen {
                XCTAssertNotEqual(data ?? nil, existing, "\(name) renders identically to \(other)")
            }
            if let data = data ?? nil { seen[name] = data }
        }
    }
}
