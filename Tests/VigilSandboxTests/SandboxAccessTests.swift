import VigilSupport
import XCTest

/// The App Store build's file access, exercised **inside a real sandbox**.
///
/// This target exists because nothing else can prove B8. The module suites run
/// in `swift test`, which is not sandboxed; `VigilAppTests` is hosted by the
/// direct build, which is not sandboxed either. Both were green for a build in
/// which the App Store app could not read `~/.claude` at all and would have
/// shown a reviewer an app that detects nothing.
///
/// The one thing here that a machine cannot do is click the open panel. So the
/// panel's *product* — an app-scoped bookmark — is made here for a directory the
/// sandbox already reaches, and everything downstream of the panel is then the
/// same code on the same path. What remains unproven by this file is one click,
/// and `docs/QA-CHECKLIST.md` says so.
final class SandboxAccessTests: XCTestCase {
    private var suite = ""
    private var defaults = UserDefaults.standard

    override func setUp() {
        super.setUp()
        suite = "vigil.sandbox.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite) ?? .standard
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    /// If this fails, nothing else in the file means anything: the tests would
    /// be proving the behaviour of an unsandboxed process.
    func testTheHostIsActuallySandboxed() {
        XCTAssertTrue(
            NSHomeDirectory().contains("/Containers/"),
            "the test host is not sandboxed — home is \(NSHomeDirectory())")
        XCTAssertNotNil(
            ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"]
                ?? (NSHomeDirectory().contains("/Containers/") ? "" : nil))
    }

    /// The trap that produced the original bug. Inside a sandbox
    /// `homeDirectoryForCurrentUser` is the container, so `~/.claude` built from
    /// it points at a directory that does not exist and never will.
    func testFoundationsHomeIsTheContainerAndUserHomeIsNot() {
        let foundation = FileManager.default.homeDirectoryForCurrentUser
        XCTAssertTrue(
            foundation.path.contains("/Containers/"),
            "expected the container, got \(foundation.path)")
        XCTAssertFalse(
            UserHome.real.path.contains("/Containers/"),
            "UserHome.real followed Foundation into the container")
        XCTAssertNotEqual(UserHome.real, foundation)
    }

    /// The denial is real, not assumed. Without a grant the sandbox refuses the
    /// account's own `~/.claude`, and `hasAccess` says so rather than guessing.
    func testWithoutAGrantTheRealClaudeFolderIsUnreachable() throws {
        let access = BookmarkFileAccess.claudeHome(store: DefaultsBookmarkStore(defaults: defaults))
        XCTAssertFalse(access.isGranted, "a fresh store claims a grant it never had")
        XCTAssertFalse(access.hasAccess(to: access.root))

        XCTAssertThrowsError(try access.withAccess(to: access.root) { $0 }) { error in
            XCTAssertEqual(error as? FileAccessError, .noBookmark(access.root))
        }
    }

    /// The panel's product, on the panel's path. A directory the sandbox already
    /// reaches stands in for the one the user would pick; from `grant` onwards
    /// this is the shipping code.
    func testAGrantSurvivesARelaunchAndReads() throws {
        let root = try scratchDirectory()
        let file = root.appendingPathComponent("transcript.jsonl")
        try Data("{}\n".utf8).write(to: file)

        let store = DefaultsBookmarkStore(defaults: defaults)
        let granting = BookmarkFileAccess(root: root, store: store)
        try granting.grant(root)
        XCTAssertTrue(granting.isGranted, "the grant did not take")

        // A second instance reading the same store is what the next launch is.
        let relaunched = BookmarkFileAccess(root: root, store: store)
        XCTAssertTrue(relaunched.isGranted, "the bookmark did not survive a relaunch")
        XCTAssertTrue(relaunched.hasAccess(to: file))

        let contents = try relaunched.withAccess(to: file) { try Data(contentsOf: $0) }
        XCTAssertEqual(String(decoding: contents, as: UTF8.self), "{}\n")
    }

    /// A scoped resource left open exhausts a per-process limit and detection
    /// then dies with no visible cause. The throwing path is the one that leaks.
    func testAccessIsBalancedEvenWhenTheReadThrows() throws {
        let root = try scratchDirectory()
        let store = DefaultsBookmarkStore(defaults: defaults)
        let access = BookmarkFileAccess(root: root, store: store)
        try access.grant(root)

        struct Boom: Error {}
        for _ in 0..<200 {
            XCTAssertThrowsError(try access.withAccess(to: root) { _ in throw Boom() })
        }
        // Still working after two hundred failed reads. An unbalanced start
        // would have run the process out of scoped resources by now.
        let file = root.appendingPathComponent("after.txt")
        try access.withAccess(to: root) { _ in try Data("ok".utf8).write(to: file) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    /// Somewhere the sandbox can write without anybody granting anything.
    private func scratchDirectory() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("vigil-sandbox-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
}
