import AppKit
import XCTest

@testable import Belay

/// The card is an advertisement Belay sends out with no chance to explain
/// itself, so these tests cover the two ways it can embarrass the app: coming
/// out blank, and claiming something that did not happen.
@MainActor
final class ShareCardTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_760_000_000)

    private func fortnight() -> UsageStatistics {
        var statistics = UsageStatistics()
        for offset in 0..<10 {
            let date = day.addingTimeInterval(Double(offset) * 86_400)
            statistics.record(hold: 2400 + Double(offset) * 600, away: 1800, on: date)
        }
        return statistics
    }

    private func nothingRescued() -> UsageStatistics {
        var statistics = UsageStatistics()
        statistics.record(hold: 3600, away: 0, on: day)
        statistics.record(hold: 1800, away: AwayTime.threshold - 1, on: day)
        return statistics
    }

    func testCardRendersAtTheOpenGraphPixelSize() throws {
        let bitmap = try XCTUnwrap(ShareCardRenderer.cgImage(for: fortnight()))
        XCTAssertEqual(bitmap.width, Int(ShareCardRenderer.pixelSize.width))
        XCTAssertEqual(bitmap.height, Int(ShareCardRenderer.pixelSize.height))

        let image = try XCTUnwrap(ShareCardRenderer.image(for: fortnight()))
        XCTAssertEqual(image.size, ShareCardRenderer.size, "point size must stay 1200x630")
    }

    /// A renderer that inherits no window is perfectly capable of producing a
    /// fully transparent, or fully black, 2400x1260 rectangle.
    func testCardIsNeitherBlankNorASolidBlock() throws {
        let bitmap = try XCTUnwrap(ShareCardRenderer.cgImage(for: fortnight()))
        let samples = Self.samples(of: bitmap)
        XCTAssertFalse(samples.isEmpty)

        XCTAssertTrue(samples.allSatisfy { $0.alpha > 0.99 }, "the card must be opaque")
        let luminance = samples.map(\.luminance)
        let darkest = try XCTUnwrap(luminance.min())
        let brightest = try XCTUnwrap(luminance.max())
        XCTAssertLessThan(darkest, 0.2, "the plate should be dark")
        XCTAssertGreaterThan(brightest, 0.5, "nothing on the card is lit")
        let levels = Set(luminance.map { Int($0 * 40) })
        XCTAssertGreaterThan(levels.count, 4, "a solid block is not a card")
    }

    func testNothingRescuedIsNeverDescribedAsSaved() throws {
        let statistics = nothingRescued()
        XCTAssertEqual(statistics.totalRescued, 0)

        let content = ShareCardContent(statistics, now: day)
        // The sentence is where a claim can be made, so that is what this
        // guards. A figure labelled "runs saved" reading zero claims nothing.
        XCTAssertFalse(content.caption.lowercased().contains("saved"), content.caption)
        XCTAssertFalse(content.caption.lowercased().contains("interrupted"), content.caption)
        XCTAssertEqual(content.figures.first?.value, "0", "the rescue figure disagrees")
        XCTAssertFalse(ShareStatistics.linked(statistics).lowercased().contains("saved"))
        XCTAssertNotNil(ShareCardRenderer.cgImage(for: statistics), "it still gets a card")
    }

    /// One rescue is spelled, not counted. "1 run" beside a headline number
    /// reads as a second statistic rather than as the end of the sentence.
    func testOneRescueIsSingularOnTheCard() {
        var statistics = UsageStatistics()
        statistics.record(hold: 3600, away: 3600, on: day)
        let caption = ShareCardContent(statistics, now: day).caption
        // Spelled, in whatever language: a numeral here reads as a second
        // statistic beside the headline rather than as the end of a sentence.
        XCTAssertFalse(caption.contains(where: \.isNumber), caption)
    }

    /// An injected pasteboard, because a test has no business clearing the
    /// user's clipboard.
    func testCopyPutsBothTheCardAndTheWordsOnOnePasteboard() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.perfectoweb.belay.tests.card"))
        defer { pasteboard.releaseGlobally() }

        XCTAssertTrue(ShareStatistics.copy(fortnight(), to: pasteboard))

        let images = try XCTUnwrap(pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage])
        XCTAssertEqual(images.count, 1)
        let text = try XCTUnwrap(pasteboard.string(forType: .string))
        XCTAssertTrue(text.contains(Branding.repositorySlug), text)
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 1, "one item, not two pastes")
    }

    func testSharingItemsCarryTheCardTheTextAndTheLink() {
        let items = ShareStatistics.sharingItems(from: fortnight())
        XCTAssertTrue(items.contains { $0 is NSImage })
        XCTAssertTrue(items.contains { $0 is String })
        XCTAssertTrue(items.contains { $0 is URL })
    }

    // MARK: - pixels

    private struct Sample {
        let luminance: Double
        let alpha: Double
    }

    /// Redrawn into a known RGBA8 buffer rather than trusting whatever colour
    /// space the renderer chose, so the numbers above mean the same thing on
    /// every machine.
    private static func samples(of image: CGImage, grid: Int = 24) -> [Sample] {
        let width = image.width
        let height = image.height
        let bytes = width * height * 4
        let pixels = UnsafeMutablePointer<UInt8>.allocate(capacity: bytes)
        pixels.initialize(repeating: 0, count: bytes)
        defer { pixels.deallocate() }

        guard
            let context = CGContext(
                data: pixels, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return [] }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return (0..<grid).flatMap { row -> [Sample] in
            (0..<grid).map { column -> Sample in
                let x = width * column / grid + width / (grid * 2)
                let y = height * row / grid + height / (grid * 2)
                let offset = (y * width + x) * 4
                let red = Double(pixels[offset]) / 255
                let green = Double(pixels[offset + 1]) / 255
                let blue = Double(pixels[offset + 2]) / 255
                return Sample(
                    luminance: 0.2126 * red + 0.7152 * green + 0.0722 * blue,
                    alpha: Double(pixels[offset + 3]) / 255)
            }
        }
    }
}
