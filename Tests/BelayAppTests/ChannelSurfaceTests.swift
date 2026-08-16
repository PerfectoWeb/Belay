import BelayChannel
import XCTest

@testable import Belay

/// The things that must differ between the two channels, asserted rather than
/// remembered. Every one of these was got wrong once: a payment link shipped in
/// the sandboxed build, and About promised a daily update check in a build with
/// no way to make one.
final class ChannelSurfaceTests: XCTestCase {
    func testTheDonateLinkExistsOnlyWhereItIsAllowed() {
        let shown = DistributionChannel.current == .direct && Branding.donateURL != nil
        if DistributionChannel.current == .appStore {
            XCTAssertFalse(shown, "a payment link in a Mac App Store build is a rejection")
        }
    }

    func testTheReviewLinkPointsAtBelaysOwnListing() throws {
        let review = try XCTUnwrap(Branding.appStoreReviewURL)
        XCTAssertEqual(review.scheme, "macappstore")
        XCTAssertTrue(
            review.absoluteString.contains("action=write-review"),
            "the link should open the review sheet, not just the page: \(review)")
        let identifier = try XCTUnwrap(Branding.appStoreID)
        XCTAssertTrue(review.absoluteString.contains(identifier), "\(review) is not Belay's listing")
    }

    /// The App Store build cannot check for updates, so it must not say it
    /// does. The direct build can, so it must.
    func testThePrivacyPromiseMatchesWhatTheChannelCanDo() {
        let promise = PrivacyPromise.forThisChannel
        let mentionsUpdates = promise.contains("update check") || promise.contains("обновлен")
        XCTAssertEqual(
            mentionsUpdates, DistributionChannel.current == .direct,
            "About and the entitlements disagree about whether this build reaches the network")
    }

    /// The hook bridge and the entitlement that lets it bind are one decision.
    /// If this ever says true under sandbox again, `Belay-MAS.entitlements` has
    /// to grow `com.apple.security.network.server` back, and that is the
    /// entitlement App Review rejected twice: it supports a feature that cannot
    /// work in a container, because the installer writes into
    /// `~/.claude/settings.json` and the sandbox home is the container.
    @MainActor
    func testTheAppStoreBuildHasNoHookBridge() {
        XCTAssertEqual(
            PreciseDetection.isSupported, DistributionChannel.current == .direct,
            "the listener and the entitlements file disagree about this build")
    }

    @MainActor
    func testTheTwoWaysOfAskingWhichChannelAgree() {
        let fromCompileCondition = ReleaseChecker.isSupported
        XCTAssertEqual(
            fromCompileCondition, DistributionChannel.current == .direct,
            "the compile condition and the Info.plist key disagree about the channel")
    }
}
