import Foundation

/// One tip option, as data. Product identifiers are placeholders until the
/// user's App Store Connect account exists (BLOCKERS.md B2).
public struct Tip: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String

    public init(id: String, title: String, subtitle: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
    }
}

/// The one seam between the two distribution channels: the App Store build must
/// use StoreKit consumables, and a link-based tip in a MAS build is a guideline
/// violation. The direct build supplies a link-based implementation of the same
/// protocol (docs/06).
public protocol TipJarProviding: Sendable {
    /// False until real products exist; the UI stays hidden while it is false.
    var isAvailable: Bool { get }
    func availableTips() async -> [Tip]
    func purchase(_ tip: Tip) async throws
}
