import Foundation

/// Which of the two channels in docs/06 this build belongs to.
///
/// The app target's `BELAY_MAS` compile condition does not reach a local
/// SwiftPM target: Xcode builds package targets from the package's own
/// settings, so `#if BELAY_MAS` inside BelayKit is false in every build
/// (verified with a `#warning` probe under Xcode 26.6). The channel therefore
/// travels in the bundle, where `project.yml` sets it per target, and
/// `#if BELAY_MAS` stays in the app target where it actually means something.
public enum DistributionChannel: String, Sendable {
    case direct
    case appStore

    public static let infoKey = "BelayDistributionChannel"

    public static var current: DistributionChannel {
        channel(named: Bundle.main.object(forInfoDictionaryKey: infoKey) as? String)
    }

    /// An unlabelled bundle — a test host, a preview, a hand-rolled build —
    /// resolves to `.appStore`, the channel with the rules. Guessing wrong that
    /// way hides the tip UI; guessing the other way puts a payment link in a
    /// sandboxed build, which is a guideline violation.
    static func channel(named raw: String?) -> DistributionChannel {
        raw.flatMap(DistributionChannel.init(rawValue:)) ?? .appStore
    }
}
