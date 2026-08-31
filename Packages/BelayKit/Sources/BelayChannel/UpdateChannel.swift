import Foundation

/// The second of the two seams between distribution channels (docs/06): Sparkle
/// in the direct build, nothing at all in the App Store build, which ships its
/// own updater and rejects ours.
///
/// It lives beside `DistributionChannel` because it is the one thing that
/// answer is used for outside the app target, and a module per protocol is not
/// a structure, it is a filing system.
public protocol UpdateChannel: Sendable {
    var isSupported: Bool { get }
    func checkForUpdates()
}

/// What every build uses today. Sparkle is not wired up: there is no EdDSA
/// signing key and no appcast to point at (docs/BLOCKERS.md (git history) B3), and an updater
/// aimed at a placeholder URL is worse than no updater.
public struct NoUpdateChannel: UpdateChannel {
    public init() {}

    public var isSupported: Bool { false }

    public func checkForUpdates() {}
}

/// The appcast Sparkle would read. Kept next to `NoUpdateChannel` so that
/// turning updates on is a matter of filling this in, not of finding it.
public enum Appcast {
    /// The project's own site, which is the `gh-pages` branch of this
    /// repository, so the feed is published by the same push that publishes the
    /// site and there is no second host to keep alive. HTTPS, and it has to be:
    /// an appcast over HTTP is a remote code execution path with extra steps.
    public static let feedURL = "https://perfectoweb.github.io/Belay/appcast.xml"

    /// Sparkle checks on its own schedule but never installs without the user
    /// saying so. People running a system utility get to choose when it
    /// restarts (docs/06).
    public static let checksAutomatically = true
    public static let installsAutomatically = false

    public static var isConfigured: Bool { false }
}
