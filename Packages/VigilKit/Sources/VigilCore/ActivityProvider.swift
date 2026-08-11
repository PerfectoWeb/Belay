import Foundation

public enum ProviderAvailability: Sendable, Equatable {
    case ready
    /// Usable once the user does the described thing (grant folder access, …).
    case needsSetup(String)
    /// Not usable on this machine at all; the string says why.
    case unavailable(String)

    public var isReady: Bool { self == .ready }
}

/// Metadata the Providers settings pane is generated from, so adding a provider
/// never means hand-writing another settings section (docs/02).
public struct ProviderDescriptor: Sendable, Equatable, Identifiable {
    public let id: ProviderID
    public let displayName: String
    public let summary: String
    /// SF Symbol name for the row and the session list.
    public let symbolName: String
    /// Whether this provider offers an exact-detection (hook) integration.
    public let supportsPreciseDetection: Bool

    public init(
        id: ProviderID,
        displayName: String,
        summary: String,
        symbolName: String,
        supportsPreciseDetection: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.summary = summary
        self.symbolName = symbolName
        self.supportsPreciseDetection = supportsPreciseDetection
    }
}

/// One source of activity signals.
///
/// Conforming types are actors that own whatever watching machinery they need
/// and publish a single `AsyncStream`. Adding a provider should touch this
/// protocol, one new file, and the registry — nothing else.
public protocol ActivityProvider: Actor {
    nonisolated var descriptor: ProviderDescriptor { get }
    var availability: ProviderAvailability { get async }
    var signals: AsyncStream<ActivitySignal> { get }

    func start() async throws
    func stop() async
}

extension ActivityProvider {
    nonisolated public var id: ProviderID { descriptor.id }
}
