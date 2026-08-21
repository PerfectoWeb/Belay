import AppKit
import BelayCore
import SwiftUI
import XCTest

@testable import Belay

/// The rule for when the countdown belongs on the dimmed screen, kept pure so
/// it needs no display to test.
@MainActor
final class DimClockTests: XCTestCase {
    private let timer = AlwaysOnTimer(duration: 7200, deadline: Date() + 3600)

    func testShowsOnlyWhenDimmedWantedAndCounting() {
        XCTAssertTrue(DimClock.shouldShow(dimmed: true, enabled: true, timer: timer))
        XCTAssertFalse(
            DimClock.shouldShow(dimmed: false, enabled: true, timer: timer),
            "a lit screen needs no overlay")
        XCTAssertFalse(
            DimClock.shouldShow(dimmed: true, enabled: false, timer: timer),
            "the toggle must be respected")
        XCTAssertFalse(
            DimClock.shouldShow(dimmed: true, enabled: true, timer: nil),
            "an unbounded hold has nothing to count")
    }

    /// Renders the digits to a PNG for eye checks, beside the panel frames.
    func testWriteDimClockFrame() throws {
        guard let folder = ProcessInfo.processInfo.environment["BELAY_FRAMES"] else {
            throw XCTSkip("set BELAY_FRAMES to a directory to write the frames")
        }
        let out = URL(fileURLWithPath: folder)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        // On black at full brightness; on the real screen the gamma ramp dims
        // these digits with everything else.
        let view = DimClockView(deadline: Date() + 4321)
            .padding(60)
            .background(Color.black)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            return XCTFail("no bitmap")
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("no png")
        }
        try png.write(to: out.appendingPathComponent("dim-clock.png"))
    }
}
