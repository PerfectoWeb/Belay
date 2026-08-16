import Foundation
import Testing

@testable import BelayChannel

@Suite struct DistributionChannelTests {
    @Test(arguments: [("direct", DistributionChannel.direct), ("appStore", .appStore)])
    func readsTheChannelTheBundleDeclares(raw: String, expected: DistributionChannel) {
        #expect(DistributionChannel.channel(named: raw) == expected)
    }

    /// A build that forgot to declare its channel must fall back to the
    /// restrictive one. The failure mode in the other direction is a payment
    /// link inside a sandboxed build.
    @Test(arguments: [nil, "", "Direct", "mas"])
    func fallsBackToAppStoreForAnythingUnrecognised(raw: String?) {
        #expect(DistributionChannel.channel(named: raw) == .appStore)
    }

    /// The raw values are written into `Info.plist` by `project.yml` and read
    /// back here. If either side is renamed without the other, every build
    /// silently becomes an App Store build, so the strings are pinned.
    @Test func theRawValuesAreTheOnesTheBundleCarries() {
        #expect(DistributionChannel.direct.rawValue == "direct")
        #expect(DistributionChannel.appStore.rawValue == "appStore")
        #expect(DistributionChannel.infoKey == "BelayDistributionChannel")
    }
}
