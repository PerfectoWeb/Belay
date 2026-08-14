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
}
