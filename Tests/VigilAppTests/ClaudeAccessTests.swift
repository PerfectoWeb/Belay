import VigilSupport
import XCTest

@testable import Vigil

/// The channel seam, from the side that can be tested: this bundle is hosted by
/// the direct target, so what it proves is that the direct build did not quietly
/// acquire the sandboxed implementation. The MAS half is proved by the
/// `Vigil-MAS` scheme compiling `ClaudeAccess`'s other branch at all — there is
/// no test host for it, and `scripts/verify-mas-build.sh` is what audits that
/// bundle (`BLOCKERS.md` B8).
@MainActor
final class ClaudeAccessTests: XCTestCase {
    func testTheDirectBuildReadsTheFolderOutright() {
        XCTAssertTrue(
            ClaudeAccess.provider is DirectFileAccess,
            "the direct build must never take a security-scoped bookmark; it is not sandboxed")
    }

    /// Nothing to grant means the onboarding button says "Start watching"
    /// instead of offering a panel that would grant nothing.
    func testThereIsNothingToGrantInTheDirectBuild() {
        XCTAssertTrue(ClaudeAccess.isGranted)
        XCTAssertTrue(ClaudeAccess.request())
    }

    /// `~/.claude` has to be the user's, not the container's. This passes
    /// trivially unsandboxed and is here because the same line is what the MAS
    /// build depends on.
    func testTheFolderIsUnderTheAccountsRealHome() {
        XCTAssertFalse(ClaudeAccess.home.path.contains("/Library/Containers/"))
        XCTAssertEqual(ClaudeAccess.folder.lastPathComponent, ".claude")
        XCTAssertEqual(ClaudeAccess.folder.deletingLastPathComponent().path, ClaudeAccess.home.path)
    }
}
