import AppKit
import SwiftUI
import XCTest

@testable import Belay

/// Renders the statistics chart's hover states to PNGs so they can be looked
/// at. Same contract as `SceneFramesTests`: no pixel assertions, only frames.
///
/// Set `BELAY_FRAMES` to a directory to write them:
///     BELAY_FRAMES=/tmp/frames swift test --filter ChartFrames
@MainActor
final class ChartFramesTests: XCTestCase {
    func testWriteHoverStates() throws {
        guard let folder = ProcessInfo.processInfo.environment["BELAY_FRAMES"] else {
            throw XCTSkip("set BELAY_FRAMES to a directory to write the frames")
        }
        let out = URL(fileURLWithPath: folder)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let days = Self.fortnight()
        let busy = days.max { $0.heldSeconds < $1.heldSeconds }
        for (name, hovered) in [("rest", nil), ("hover", busy)] {
            let view = DayBars(days: days, hovered: hovered)
                .frame(width: 360, height: 56)
                .padding(20)
                .background(Color(nsColor: .windowBackgroundColor))
                .tint(.accentColor)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage,
                let tiff = image.tiffRepresentation,
                let rep = NSBitmapImageRep(data: tiff),
                let png = rep.representation(using: .png, properties: [:])
            else {
                XCTFail("could not render \(name)")
                return
            }
            try png.write(to: out.appendingPathComponent("chart-\(name).png"))
        }
    }

    /// Two weeks with a shape: quiet start, one heavy day, two empty ones.
    private static func fortnight() -> [UsageStatistics.Day] {
        let today = Calendar.current.startOfDay(for: Date())
        return (0..<14).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: offset - 13, to: today)!
            let load = [2.0, 3, 0, 5, 4, 1, 0, 6, 9, 3, 2, 7, 5, 4][offset]
            return UsageStatistics.Day(
                date: date, heldSeconds: load * 1800, holds: Int(load),
                longestHold: load * 700, awaySeconds: load * 1200, rescued: Int(load) / 2)
        }
    }
}
