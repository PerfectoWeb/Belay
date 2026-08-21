import AppKit
import BelayCore
import SwiftUI
import XCTest

@testable import Belay

/// Renders the Always-on timer row's three faces to PNGs so they can be looked
/// at. Same contract as `ChartFramesTests`: no pixel assertions, only frames.
///
/// Set `BELAY_FRAMES` to a directory to write them:
///     BELAY_FRAMES=/tmp/frames ... -only-testing:BelayAppTests/PanelTimerFramesTests
@MainActor
final class PanelTimerFramesTests: XCTestCase {
    func testWriteTimerFaces() throws {
        guard let folder = ProcessInfo.processInfo.environment["BELAY_FRAMES"] else {
            throw XCTSkip("set BELAY_FRAMES to a directory to write the frames")
        }
        let out = URL(fileURLWithPath: folder)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let faces: [(String, BelayState, AlwaysOnTimer?)] = [
            ("unbounded", .alwaysOn, nil),
            ("counting", .alwaysOn, AlwaysOnTimer(duration: 7200, deadline: Date() + 4321)),
            ("timer-ended", .suspended(.timerEnded(7200)), AlwaysOnTimer(duration: 7200, deadline: Date())),
            ("cap-paused", .suspended(.maxDurationReached(4 * 3600)), nil)
        ]
        for (name, state, timer) in faces {
            let app = AppState()
            app.mode = .alwaysOn
            app.apply(
                CoordinatorSnapshot(
                    state: state, sessions: [], activities: [:],
                    holdReason: state.holdsAssertion ? .alwaysOn : nil,
                    holdingSince: nil, timer: timer),
                totalAwake: 754)
            let view = PanelView(state: app)
                .background(Color(nsColor: .windowBackgroundColor))
            // An `NSHostingView` snapshot, not `ImageRenderer`: the duration
            // chip is an AppKit-backed `Menu`, which the SwiftUI renderer
            // draws as a placeholder blob.
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                XCTFail("no bitmap for \(name)")
                return
            }
            host.cacheDisplay(in: host.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else {
                XCTFail("could not render \(name)")
                return
            }
            try png.write(to: out.appendingPathComponent("timer-\(name).png"))
        }
    }
}
