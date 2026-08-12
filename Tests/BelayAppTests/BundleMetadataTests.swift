import XCTest

@testable import Belay

/// Guards the Info.plist keys that make Belay a menu bar app. Getting
/// LSUIElement wrong ships a Dock icon and a very confusing bug report.
final class BundleMetadataTests: XCTestCase {
    private var appBundle: Bundle {
        let testBundle = Bundle(for: type(of: self))
        guard let host = testBundle.infoDictionary?["NSPrincipalClass"] as? String, !host.isEmpty else {
            return Bundle.main
        }
        return Bundle.main
    }

    func testRunsAsMenuBarOnlyApp() {
        XCTAssertEqual(appBundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool, true)
    }

    func testDeclaresNoNonExemptEncryption() {
        XCTAssertEqual(
            appBundle.object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption") as? Bool,
            false
        )
    }

    func testMinimumSystemVersionIsSonoma() {
        let minimum = appBundle.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String
        XCTAssertEqual(minimum, "14.0")
    }

    /// The account is `perfectoweb`; the bundle-id prefix is `perfecto-web`. They
    /// look alike and only one of them is a real GitHub account, so every link
    /// the app ships — About, the bug report, the shared statistics — is checked
    /// against the slug rather than trusted to have been typed correctly.
    func testEveryShippedLinkPointsAtTheRealAccount() {
        let links = [Branding.repositoryURL, Branding.issuesURL, Branding.supportURL, Branding.coffeeURL]
        for link in links.compactMap({ $0 }) {
            XCTAssertEqual(link.host(), "github.com", "\(link)")
            XCTAssertTrue(
                link.path().hasPrefix("/\(Branding.repositorySlug)"),
                "\(link) does not point at \(Branding.repositorySlug)")
        }
        XCTAssertFalse(
            Branding.repositorySlug.contains("-"),
            "the GitHub account has no dash — that is the bundle identifier")
    }
}
