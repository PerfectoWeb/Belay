import AppKit
import SwiftUI
import XCTest

@testable import Belay

/// Renders the welcome scene to PNGs so it can be looked at.
///
/// Not an assertion about pixels: a snapshot test that fails on a hairline is a
/// test that gets deleted. This exists because the animation has to be judged
/// by eye, and a test bundle is the only place in this project that can draw a
/// SwiftUI view without a screen, a window or a permission.
///
/// Set `BELAY_FRAMES` to a directory to write them:
///     BELAY_FRAMES=/tmp/frames swift test --filter SceneFrames
@MainActor
final class SceneFramesTests: XCTestCase {
    func testWriteFrames() throws {
        guard let folder = ProcessInfo.processInfo.environment["BELAY_FRAMES"] else {
            throw XCTSkip("set BELAY_FRAMES to a directory to write the frames")
        }
        let out = URL(fileURLWithPath: folder)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let times = stride(from: 0.0, through: OnboardingScene.loop, by: OnboardingScene.loop / 12)
        for (index, time) in times.enumerated() {
            let view = OnboardingScene.still(at: time)
                .frame(width: OnboardingScene.box.width, height: OnboardingScene.box.height)
                .background(Color(red: 0.05, green: 0.06, blue: 0.10))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage,
                let tiff = image.tiffRepresentation,
                let rep = NSBitmapImageRep(data: tiff),
                let png = rep.representation(using: .png, properties: [:])
            else {
                XCTFail("could not render frame \(index)")
                return
            }
            try png.write(to: out.appendingPathComponent(String(format: "frame-%02d.png", index)))
        }
    }

    /// The whole welcome window, once it has finished arriving.
    ///
    /// `ImageRenderer` cannot do this one. The screen is built out of state that
    /// only `onAppear` and a `task` ever set — the four blocks arriving, the
    /// greeting being written, the sky coming up — and a renderer draws a view
    /// tree without ever appearing it, so it would photograph an empty panel
    /// with everything at zero opacity.
    ///
    /// A real hosting view in a real window does run all of that. It is also
    /// the only way to see the panel's layout at all from here: photographing
    /// the running app needs Screen Recording, which is granted per program and
    /// is not granted to whatever is running the tests.
    ///
    /// What it is not: a photograph of the finished window. `cacheDisplay` draws
    /// the view's own layers and not the window's material behind them, so the
    /// half below the panel comes out blank and its text with it. The panel is
    /// what this is for, and the panel is all of it that can be trusted.
    func testWriteWelcomeScreen() throws {
        guard let folder = ProcessInfo.processInfo.environment["BELAY_FRAMES"] else {
            throw XCTSkip("set BELAY_FRAMES to a directory to write the frames")
        }
        let host = NSHostingView(
            rootView: OnboardingView(providerReady: true, onGrantAccess: {}, onDismiss: {}))
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.titled, .fullSizeContentView],
            backing: .buffered, defer: false)
        // Dark, because that is the appearance the panel was drawn against and
        // the only one the words below it are legible in here: an unstyled test
        // window comes up in Aqua and puts white text on white.
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.orderBack(nil)

        // Long enough for the greeting to be written, held and faded, and for
        // the scene behind it to have got a little way into its loop.
        let settled = Date().addingTimeInterval(5.2)
        while Date() < settled { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            XCTFail("no bitmap for the hosting view")
            return
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("could not encode the welcome screen")
            return
        }
        try png.write(
            to: URL(fileURLWithPath: folder).appendingPathComponent("welcome.png"))
    }
}
