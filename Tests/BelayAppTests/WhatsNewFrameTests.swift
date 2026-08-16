import AppKit
import SwiftUI
import XCTest

@testable import Belay

/// Photographs of the release-notes window, so its layout can be judged rather
/// than argued about. Skipped unless `BELAY_FRAMES` names a directory.
///
/// The view is given an explicit background before it is drawn. `cacheDisplay`
/// draws the view's own layers and not the window's material behind them, which
/// leaves everything below the lit panel on a transparent ground: legible in a
/// viewer that shows a white page behind it, and invisible in one that does not.
/// Painting the window's own colour underneath is the difference between a
/// picture of the window and a picture of half of it.
@MainActor
final class WhatsNewFrameTests: XCTestCase {
    /// Three shapes, because three are what break differently: one version with
    /// four items, two versions at once, and a single item.
    func testWriteWhatsNewScreens() throws {
        guard let folder = ProcessInfo.processInfo.environment["BELAY_FRAMES"] else {
            throw XCTSkip("set BELAY_FRAMES to a directory to write the frames")
        }
        let out = URL(fileURLWithPath: folder)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let extra = ReleaseNote(
            version: "1.2.0",
            items: [
                .init(symbol: "bell", title: "Quieter notifications", body: "One line, to see a short row."),
                .init(
                    symbol: "chart.bar", title: "Statistics",
                    body: "A second line here, long enough to wrap onto two of them in English.")
            ])

        for (name, notes) in [
            ("whatsnew", ReleaseNotes.all),
            ("whatsnew-two-versions", ReleaseNotes.all + [extra]),
            ("whatsnew-one-item", [ReleaseNote(version: "1.3.0", items: [ReleaseNotes.all[0].items[0]])])
        ] {
            for appearance in [NSAppearance.Name.darkAqua, .aqua] {
                try write(notes, to: out, name: "\(name)-\(appearance == .aqua ? "light" : "dark")",
                    appearance: appearance)
            }
        }
    }

    private func write(
        _ notes: [ReleaseNote], to folder: URL, name: String, appearance: NSAppearance.Name
    ) throws {
        let view = WhatsNewView(notes: notes, onDismiss: {})
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        host.appearance = NSAppearance(named: appearance)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.titled, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.orderBack(nil)

        // Long enough for the arrival to finish; everything on this screen is
        // still after that.
        let settled = Date().addingTimeInterval(1.2)
        while Date() < settled { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            XCTFail("no bitmap for \(name)")
            return
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("could not encode \(name)")
            return
        }
        try png.write(to: folder.appendingPathComponent("\(name).png"))
    }
}
