import Foundation

/// The second of the two seams between distribution channels (docs/06): Sparkle
/// in the direct build, nothing at all in the App Store build, which ships its
/// own updater and rejects ours.
///
/// This lives alongside the tip jar because both exist for the same reason —
/// they are the only two places the channels differ — and BelayTipJar is the
/// module that owns that split. A dedicated `BelayUpdates` target is the
/// tidier home and is a two-line `Package.swift` change whenever that file is
/// in scope.
public protocol UpdateChannel: Sendable {
    var isSupported: Bool { get }
    func checkForUpdates()
}

/// What every build uses today. Sparkle is not wired up: there is no EdDSA
/// signing key and no appcast to point at (BLOCKERS.md B3), and an updater
/// aimed at a placeholder URL is worse than no updater.
public struct NoUpdateChannel: UpdateChannel {
    public init() {}

    public var isSupported: Bool { false }

    public func checkForUpdates() {}
}

/// The appcast Sparkle would read. Kept next to `NoUpdateChannel` so that
/// turning updates on is a matter of filling this in, not of finding it.
public enum Appcast {
    /// PLACEHOLDER — not a real host. HTTPS only when it becomes one: an
    /// appcast over HTTP is a remote code execution path with extra steps.
    public static let feedURL = "https://updates.invalid.example/belay/appcast.xml"

    /// Sparkle checks on its own schedule but never installs without the user
    /// saying so. People running a system utility get to choose when it
    /// restarts (docs/06).
    public static let checksAutomatically = true
    public static let installsAutomatically = false

    public static var isConfigured: Bool { false }
}
