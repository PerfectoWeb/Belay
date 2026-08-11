import Foundation

/// Picks the tip jar the running channel is allowed to use.
///
/// The App Store build must never get `LinkTipJar`, so the choice is made here
/// once rather than at each call site in the UI.
public enum TipJar {
    public static func forCurrentChannel(
        support: URL,
        open: @escaping LinkTipJar.Opener,
        channel: DistributionChannel = .current
    ) -> any TipJarProviding {
        switch channel {
        case .direct: LinkTipJar(destination: support, open: open)
        case .appStore: StoreKitTipJar()
        }
    }
}
