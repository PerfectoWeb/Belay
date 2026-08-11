import Foundation

/// The direct build's tip jar: one link, opened on demand.
///
/// It takes an opener closure rather than calling `NSWorkspace` itself so that
/// VigilKit stays free of AppKit — the app passes
/// `{ NSWorkspace.shared.open($0) }` and the tests pass a spy.
public struct LinkTipJar: TipJarProviding {
    public typealias Opener = @Sendable (URL) -> Void

    private let destination: URL
    private let open: Opener

    public init(destination: URL, open: @escaping Opener) {
        self.destination = destination
        self.open = open
    }

    public var isAvailable: Bool { true }

    public func availableTips() async -> [Tip] { [TipProducts.supportLink] }

    public func purchase(_ tip: Tip) async throws {
        guard tip.id == TipProducts.supportLink.id else { throw TipJarError.unknownTip(tip.id) }
        open(destination)
    }
}
