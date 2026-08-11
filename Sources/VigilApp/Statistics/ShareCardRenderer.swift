import AppKit
import SwiftUI

/// Turns `ShareCard` into pixels.
///
/// Nothing here touches the network or the disk; the bitmap lives in memory
/// until the user hands it to a share service or the pasteboard.
@MainActor
enum ShareCardRenderer {
    /// The Open Graph ratio. Telegram, Slack, Messages and X all preview 1.91:1
    /// without cropping, so the card survives being pasted rather than being
    /// centre-cropped into nonsense.
    static let size = CGSize(width: 1200, height: 630)

    /// Rendered at 2x, i.e. a 2400x1260 bitmap, so it stays sharp when a client
    /// blows it up to the width of a chat bubble.
    static let scale: CGFloat = 2

    static var pixelSize: CGSize {
        CGSize(width: size.width * scale, height: size.height * scale)
    }

    static func cgImage(for statistics: UsageStatistics) -> CGImage? {
        let renderer = ImageRenderer(content: ShareCard(content: ShareCardContent(statistics)))
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.cgImage
    }

    /// Sized in points, so an app that inspects `size` sees 1200x630 and still
    /// gets the full-density bitmap.
    static func image(for statistics: UsageStatistics) -> NSImage? {
        guard let bitmap = cgImage(for: statistics) else { return nil }
        return NSImage(cgImage: bitmap, size: size)
    }

    static func pngData(for statistics: UsageStatistics) -> Data? {
        guard let bitmap = cgImage(for: statistics) else { return nil }
        return NSBitmapImageRep(cgImage: bitmap).representation(using: .png, properties: [:])
    }

    /// Card and words as **one** pasteboard item, so the receiving app chooses
    /// which representation it wants instead of the user pasting twice.
    @discardableResult
    static func copy(_ statistics: UsageStatistics, text: String, to pasteboard: NSPasteboard) -> Bool {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        if let bitmap = cgImage(for: statistics) {
            let representation = NSBitmapImageRep(cgImage: bitmap)
            if let png = representation.representation(using: .png, properties: [:]) {
                item.setData(png, forType: .png)
            }
            if let tiff = representation.representation(using: .tiff, properties: [:]) {
                item.setData(tiff, forType: .tiff)
            }
        }
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }
}
