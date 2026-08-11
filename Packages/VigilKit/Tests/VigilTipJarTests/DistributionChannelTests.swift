import Foundation
import Testing

@testable import VigilTipJar

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

    @Test func appStoreChannelNeverGetsTheLinkTipJar() {
        let jar = TipJar.forCurrentChannel(
            support: URL(fileURLWithPath: "/dev/null"),
            open: { _ in },
            channel: .appStore
        )

        #expect(jar is StoreKitTipJar)
        #expect(jar.isAvailable == false)
    }

    @Test func directChannelGetsTheLink() {
        let jar = TipJar.forCurrentChannel(
            support: URL(fileURLWithPath: "/dev/null"),
            open: { _ in },
            channel: .direct
        )

        #expect(jar is LinkTipJar)
    }
}
