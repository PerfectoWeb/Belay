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

    override func setUpWithError() throws {
        try super.setUpWithError()
        suite = "vigil.sandbox.\(UUID().uuidString)"
        // Not `?? .standard`. Falling open would write a real bookmark into the
        // host app's own defaults under the shipping key, and tearDown would
        // not find it to clean up.
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
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

    /// What this harness cannot test, and why — written as a test so the next
    /// person finds out in seconds rather than in an hour.
    ///
    /// Hosting an XCTest bundle in a sandboxed app changes that app's sandbox.
    /// Xcode injects
    /// `com.apple.security.temporary-exception.files.absolute-path.read-only`
    /// for `/` into the test host, alongside the mach-lookup exceptions the test
    /// runner needs. So the container is real, `NSHomeDirectory()` is the
    /// container, bookmarks behave exactly as they ship — and file reads are not
    /// denied anywhere. A test asserting "without a grant `~/.claude` cannot be
    /// read" passes for the wrong reason here, and one asserting the opposite
    /// fails for the wrong reason. Both were written before this was checked.
    ///
    /// The denial belongs to manual QA (`docs/QA-CHECKLIST.md` §9), against a
    /// build with no test bundle attached.
    func testTheTestHostIsGrantedReadsTheShippingBuildIsNot() throws {
        let injected = try hostEntitlements()
        XCTAssertNotNil(
            injected["com.apple.security.temporary-exception.files.absolute-path.read-only"],
            """
            Xcode no longer grants the test host read access to /. If that is \
            true, a denial test can finally live here — but check it fails for \
            the right reason before believing it.
            """)

        // The one that matters: our own entitlements, the ones that ship, carry
        // no filesystem exception. `scripts/verify-mas-build.sh` audits the
        // built Release binary; this catches the source going wrong first.
        let shipping = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/Entitlements/Vigil-MAS.entitlements"),
            encoding: .utf8)
        XCTAssertFalse(
            shipping.contains("temporary-exception"),
            "the shipping entitlements gained a sandbox exception")
    }

    private func hostEntitlements() throws -> [String: Any] {
        var code: SecCode?
        XCTAssertEqual(SecCodeCopySelf([], &code), errSecSuccess)
        var info: CFDictionary?
        let status = SecCodeCopySigningInformation(
            try XCTUnwrap(code) as! SecStaticCode, SecCSFlags(rawValue: kSecCSSigningInformation),
            &info)
        XCTAssertEqual(status, errSecSuccess)
        let dictionary = try XCTUnwrap(info as? [String: Any])
        return dictionary["entitlements-dict"] as? [String: Any] ?? [:]
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

    /// Every read is bracketed, including the throwing path.
    ///
    /// What this does **not** do is prove the bracket by exhaustion. Twenty
    /// thousand deliberately unbalanced starts were tried, looking for the
    /// per-process wall this test used to claim it crossed; there is no
    /// observable wall, `startAccessingSecurityScopedResource` keeps returning
    /// true, and Foundation exposes no live count. So this is a smoke test: two
    /// hundred failed reads, then one that must still work. The bracket itself
    /// is held by `withAccess`'s `defer` and by reading the code.
    func testReadsKeepWorkingAfterTwoHundredThrow() throws {
        let root = try scratchDirectory()
        let access = BookmarkFileAccess(root: root, store: DefaultsBookmarkStore(defaults: defaults))
        try access.grant(root)

        struct Boom: Error {}
        for _ in 0..<200 {
            XCTAssertThrowsError(try access.withAccess(to: root) { _ in throw Boom() })
        }

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

/// Somewhere for the probe's bookmark to live that is not the test's own store.
