import AppKit
import BelaySettings
import BelayCore
import BelayProviders
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

/// The dimming rows as they read on this machine, for eye checks: the
/// explanation quotes the live display-off delay.
@MainActor
final class NightDimmingGroupFrameTests: XCTestCase {
    func testWriteGroupFrame() throws {
        guard let folder = ProcessInfo.processInfo.environment["BELAY_FRAMES"] else {
            throw XCTSkip("set BELAY_FRAMES to a directory to write the frames")
        }
        let view = VStack(alignment: .leading) { NightDimmingGroup(settings: SettingsStore()) }
            .frame(width: 520)
            .padding(20)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("dim-group.png"))
    }
}

/// Two digits per unit, always.
final class CountdownFormatTests: XCTestCase {
    func testPadsEveryUnit() {
        XCTAssertEqual(Countdown.string(remaining: 2 * 3600 + 30 * 60), "02:30:00")
        XCTAssertEqual(Countdown.string(remaining: 119), "00:01:59")
        XCTAssertEqual(Countdown.string(remaining: 5), "00:00:05")
        XCTAssertEqual(Countdown.string(remaining: 12 * 3600), "12:00:00")
        XCTAssertEqual(Countdown.string(remaining: 3600), "01:00:00")
        XCTAssertEqual(Countdown.string(remaining: 3599), "00:59:59", "no unit is dropped on the way down")
        XCTAssertEqual(Countdown.string(remaining: -3), "00:00:00", "never counts below zero")
    }
}

/// The Providers pane with the two built-in tiles, for eye checks.
@MainActor
final class ProvidersPaneFrameTests: XCTestCase {
    func testWritePaneFrame() throws {
        guard let folder = ProcessInfo.processInfo.environment["BELAY_FRAMES"] else {
            throw XCTSkip("set BELAY_FRAMES to a directory to write the frames")
        }
        let app = AppState()
        app.apply(providers: [
            ProviderStatus(
                descriptor: ProviderDescriptor(
                    id: .claudeCode, displayName: "Claude Code", summary: "", symbolName: "sparkles",
                    supportsPreciseDetection: true),
                availability: .ready, isEnabled: true, lastSignal: Date() - 140),
            ProviderStatus(
                descriptor: ProviderDescriptor(
                    id: .codex, displayName: "Codex", summary: "", symbolName: "curlybraces",
                    supportsPreciseDetection: false),
                availability: .needsSetup("Grant access to ~/.codex"), isEnabled: true, lastSignal: nil),
        ])
        let view = VStack(alignment: .leading) {
            ProvidersSettingsPane(state: app, precise: PreciseDetection(), targets: [], onTargetsChanged: { _ in })
        }
        .frame(width: SettingsPane.width)
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("providers.png"))
    }
}
