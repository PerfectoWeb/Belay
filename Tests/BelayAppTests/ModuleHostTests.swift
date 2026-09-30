import BelayModules
import XCTest

@testable import Belay

/// The modules move files, so nothing here touches a real folder or the real
/// Trash: a scratch preferences suite, a folder under the temporary directory,
/// and a sweeper whose "Trash" is a list.
@MainActor
final class ModuleHostTests: XCTestCase {
    private var defaults: UserDefaults?
    private var suiteName = ""
    private var folder = URL(fileURLWithPath: "/")
    private let trashed = TrashedList()

    override func setUp() async throws {
        suiteName = "com.perfectoweb.belay.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        folder = FileManager.default.temporaryDirectory
            .appending(path: "belay-modules-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeHost(now: @escaping @Sendable () -> Date = { Date() }) throws -> ModuleHost {
        let defaults = try XCTUnwrap(defaults)
        let trashed = trashed
        let sweeper = ScreenshotSweeper(
            list: { try ScreenshotFolder.candidates(in: $0) },
            trash: { url in
                try FileManager.default.removeItem(at: url)
                trashed.add(url.lastPathComponent)
            }
        )
        let folder = folder
        return ModuleHost(
            defaults: defaults,
            screenshots: ScreenshotCleaner(defaults: defaults, sweeper: sweeper, now: now),
            microphone: MicKeepWarm(
                defaults: defaults, tap: FakeTap(), surroundings: FakeMac().surroundings),
            autoAllow: AutoAllower(defaults: defaults, screen: FakeScreen()),
            captureFolder: { folder }
        )
    }

    /// A file macOS would recognise as a screenshot, taken `age` seconds ago.
    @discardableResult
    private func shoot(_ name: String, age: TimeInterval) throws -> URL {
        let url = folder.appending(path: name)
        try Data("pixels".utf8).write(to: url)
        let mark = try PropertyListSerialization.data(
            fromPropertyList: true, format: .binary, options: 0)
        let status = mark.withUnsafeBytes {
            setxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, $0.count, 0, 0)
        }
        XCTAssertEqual(status, 0)
        let taken = Date().addingTimeInterval(-age)
        try FileManager.default.setAttributes(
            [.creationDate: taken, .modificationDate: taken], ofItemAtPath: url.path)
        return url
    }

    private func sweep(_ host: ModuleHost, _ pass: ScreenshotCleaner.Pass) {
        let done = expectation(description: "pass finished")
        host.screenshots.sweep(pass) { done.fulfill() }
        wait(for: [done], timeout: 5)
    }

    func testInstallingSwitchesTheModuleOnWithTheCaptureFolder() throws {
        let host = try makeHost()
        defer { host.stop() }

        host.install(.screenshotCleaner)

        XCTAssertTrue(host.ledger.isEnabled(.screenshotCleaner))
        XCTAssertEqual(host.screenshots.rules.folders, [folder.standardizedFileURL.path])
        XCTAssertTrue(host.screenshots.isRunning)
        XCTAssertNotNil(host.screenshots.activeSince)
    }

    func testInstallingDoesNotEmptyTheDesk() throws {
        try shoot("from last week.png", age: 7 * 86_400)
        let host = try makeHost()
        defer { host.stop() }

        host.install(.screenshotCleaner)
        sweep(host, .automatic)

        XCTAssertEqual(trashed.names, [])
        XCTAssertEqual(host.screenshots.trashedTotal, 0)
    }

    func testCleanUpNowMovesWhatIsPastItsAge() throws {
        try shoot("old.png", age: 5 * 3600)
        try shoot("fresh.png", age: 60)
        let host = try makeHost()
        defer { host.stop() }
        host.install(.screenshotCleaner)

        sweep(host, .requested)

        XCTAssertEqual(trashed.names, ["old.png"])
        XCTAssertEqual(host.screenshots.trashedTotal, 1)
        XCTAssertEqual(try XCTUnwrap(defaults).integer(forKey: ScreenshotCleaner.tallyKey), 1)
    }

    func testOnceTheGraceHasPassedTheTimerMovesThem() throws {
        try shoot("old.png", age: 5 * 3600)
        let clock = Clock()
        let host = try makeHost(now: { clock.now })
        defer { host.stop() }
        host.install(.screenshotCleaner)

        clock.advance(by: 4 * 3600 + 1)
        sweep(host, .automatic)

        XCTAssertEqual(trashed.names, ["old.png"])
    }

    func testSwitchingOffStopsAndKeepsTheSettings() throws {
        let host = try makeHost()
        host.install(.screenshotCleaner)
        host.screenshots.rules.age = 8 * 3600

        host.setEnabled(false, for: .screenshotCleaner)

        XCTAssertFalse(host.screenshots.isRunning)
        XCTAssertTrue(host.ledger.isInstalled(.screenshotCleaner))
        XCTAssertEqual(host.screenshots.rules.age, 8 * 3600)
    }

    func testRemovingForgetsEverything() throws {
        let host = try makeHost()
        host.install(.screenshotCleaner)
        host.browsing.expanded = .screenshotCleaner

        host.remove(.screenshotCleaner)

        let defaults = try XCTUnwrap(defaults)
        XCTAssertFalse(host.ledger.isInstalled(.screenshotCleaner))
        XCTAssertFalse(host.screenshots.isRunning)
        XCTAssertEqual(host.screenshots.rules, ScreenshotRules())
        XCTAssertNil(host.browsing.expanded)
        XCTAssertNil(defaults.object(forKey: ScreenshotRules.defaultsKey))
        XCTAssertNil(defaults.object(forKey: ScreenshotCleaner.sinceKey))
        XCTAssertNil(defaults.object(forKey: ModuleLedger.defaultsKey))
    }

    func testARelaunchCarriesOnWithoutRestartingTheGrace() throws {
        let first = try makeHost()
        first.install(.screenshotCleaner)
        let since = first.screenshots.activeSince
        first.stop()

        let second = try makeHost()
        defer { second.stop() }
        second.start()

        XCTAssertTrue(second.screenshots.isRunning)
        XCTAssertEqual(second.screenshots.activeSince, since)
    }

    func testAModuleSwitchedOffStaysOffAtLaunch() throws {
        let first = try makeHost()
        first.install(.screenshotCleaner)
        first.setEnabled(false, for: .screenshotCleaner)

        let second = try makeHost()
        second.start()

        XCTAssertFalse(second.screenshots.isRunning)
    }

    func testTheListFollowsTheSearchAndTheFilter() throws {
        let host = try makeHost()
        defer { host.stop() }
        XCTAssertEqual(host.shown.map(\.id), ModuleDescriptor.offered().map(\.id))

        host.browsing.query = "microphone"
        XCTAssertEqual(host.shown.map(\.id), [.micKeepWarm])
        host.browsing.query = ""

        host.browsing.scope = .installed
        XCTAssertTrue(host.shown.isEmpty)

        host.install(.screenshotCleaner)
        XCTAssertEqual(host.shown.map(\.id), [.screenshotCleaner])

        host.browsing.query = "no such module"
        XCTAssertTrue(host.shown.isEmpty)
    }

    /// The sandbox forbids pressing a button in another app, so the App
    /// Store build must not offer the module that does.
    func testTheAppStoreBuildOffersOnlyWhatTheSandboxAllows() {
        let offered = ModuleDescriptor.offered(in: .appStore).map(\.id)
        XCTAssertEqual(offered, [.screenshotCleaner, .micKeepWarm])
        XCTAssertTrue(ModuleDescriptor.offered(in: .direct).map(\.id).contains(.autoAllow))
    }

    func testEveryModuleIsOfferedSomewhere() {
        for module in ModuleDescriptor.all {
            XCTAssertFalse(module.channels.isEmpty, module.id.rawValue)
        }
        XCTAssertEqual(
            Set(ModuleDescriptor.all.map(\.id)).count, ModuleDescriptor.all.count,
            "two modules share a name")
    }
}

/// What the test sweeper "moved to the Trash". Written off the main thread.
private final class TrashedList: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [String] = []

    func add(_ name: String) { lock.withLock { list.append(name) } }

    var names: [String] { lock.withLock { list.sorted() } }
}

/// A clock a test can move. Read off the main thread by the cleaner.
private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var moment = Date()

    var now: Date { lock.withLock { moment } }

    func advance(by seconds: TimeInterval) { lock.withLock { moment += seconds } }
}
