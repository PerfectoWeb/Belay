import AppKit
import BelayModules
import SwiftUI
import XCTest

@testable import Belay

/// Renders the Modules pane to PNGs so it can be looked at. Same contract as
/// `SceneFramesTests`: no pixel assertions, only frames.
///
///     TEST_RUNNER_BELAY_FRAMES=/tmp/frames xcodebuild test -only-testing ...
@MainActor
final class ModulesPaneFramesTests: XCTestCase {
    func testWriteThePaneInItsStates() throws {
        guard let folder = ProcessInfo.processInfo.environment["BELAY_FRAMES"] else {
            throw XCTSkip("set BELAY_FRAMES to a directory to write the frames")
        }
        let out = URL(fileURLWithPath: folder)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let suite = "com.perfectoweb.belay.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let sweeper = ScreenshotSweeper(list: { _ in [] }, trash: { _ in })
        let screen = FakeScreen()
        let processes = FakeProcesses()
        let host = ModuleHost(
            defaults: defaults,
            screenshots: ScreenshotCleaner(defaults: defaults, sweeper: sweeper),
            microphone: MicKeepWarm(
                defaults: defaults, tap: FakeTap(name: "MacBook Pro Microphone"),
                surroundings: FakeMac().surroundings),
            autoAllow: AutoAllower(defaults: defaults, screens: [.claude: screen]),
            nudge: Nudger(
                defaults: defaults, sounds: FakeSounds(), notices: FakeNotices(),
                finder: FakeAgentApps()),
            orphans: OrphanWatcher(defaults: defaults, source: processes),
            captureFolder: { URL(fileURLWithPath: NSHomeDirectory() + "/Desktop") }
        )
        defer { host.stop() }

        try write("modules-offered", host, to: out)
        host.install(.screenshotCleaner)
        try write("modules-installed", host, to: out)
        host.browsing.expanded = .screenshotCleaner
        try write("modules-settings", host, to: out)
        host.setEnabled(false, for: .screenshotCleaner)
        host.browsing.expanded = nil
        try write("modules-off", host, to: out)
        host.browsing.query = "telescope"
        try write("modules-no-match", host, to: out)
        host.browsing.query = ""

        host.install(.micKeepWarm)
        host.browsing.expanded = .micKeepWarm
        let warm = expectation(description: "warm")
        Task {
            while host.microphone.warmth != .warm { try? await Task.sleep(for: .milliseconds(10)) }
            warm.fulfill()
        }
        wait(for: [warm], timeout: 5)
        try write("modules-microphone", host, to: out)

        host.install(.nudge)
        try write("modules-nudge-installed", host, to: out)
        host.browsing.expanded = .nudge
        try write("modules-nudge-settings", host, to: out)

        host.install(.autoAllow)
        host.browsing.expanded = .autoAllow
        try write("modules-autoallow-empty", host, to: out)
        for site in ["cytron.local", "localhost", "shop.test"] {
            screen.show(FakeScreen.access(to: site))
        }
        let looked = expectation(description: "looked")
        host.autoAllow.tick { looked.fulfill() }
        wait(for: [looked], timeout: 5)
        host.autoAllow.rules.scope = .everything
        try write("modules-autoallow-wide", host, to: out)
        screen.trust(false)
        let again = expectation(description: "looked again")
        host.autoAllow.tick { again.fulfill() }
        wait(for: [again], timeout: 5)

        host.install(.orphanWatch)
        host.browsing.expanded = .orphanWatch
        try write("modules-orphans-empty", host, to: out)
        processes.put(100, "claude")
        processes.put(101, "zsh", parent: 100)
        processes.put(102, "node", parent: 101, started: 5)
        processes.put(103, "next-server", parent: 101, started: 40)
        host.orphans.sweep()
        processes.drop(100)
        processes.drop(101)
        host.orphans.sweep()
        try write("modules-orphans-two", host, to: out)
        host.browsing.expanded = nil
        try write("modules-all-installed", host, to: out)
    }

    private func write(_ name: String, _ host: ModuleHost, to out: URL) throws {
        for (scheme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let view = SettingsStack { ModulesPane(host: host) }
                .background(Color(nsColor: .windowBackgroundColor))
            let hosting = NSHostingView(rootView: view)
            // In a window, never shown: AppKit-backed controls draw nothing
            // until they have one.
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: SettingsPane.width, height: 400),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            let size = NSSize(width: SettingsPane.width, height: hosting.fittingSize.height)
            window.setContentSize(size)
            hosting.frame = NSRect(origin: .zero, size: size)
            hosting.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try png.write(to: out.appendingPathComponent("\(name)-\(scheme).png"))
        }
    }
}
