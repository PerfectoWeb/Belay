import Foundation

/// Abstracts the one real difference between the direct and Mac App Store
/// builds: whether reaching `~/.claude` needs a security-scoped bookmark.
///
/// The direct build reads the path outright; the sandboxed build resolves a
/// bookmark the user granted through an open panel. Detection code depends on
/// this protocol and never on which build it is running in (docs/06).
public protocol FileAccessProvider: Sendable {
    /// Whether `url` can be read right now without further user interaction.
    func hasAccess(to url: URL) -> Bool

    /// Runs `body` with access held, releasing it afterwards even on throw.
    func withAccess<T>(to url: URL, _ body: (URL) throws -> T) throws -> T

    /// True only when this access can see that `url` does not exist at all.
    /// Unreadable and absent look the same to a sandboxed build, which is
    /// why the default says nothing; the direct build can tell them apart,
    /// and the difference is "grant the folder" versus "the tool is not
    /// installed", two very different things to tell a person.
    func isKnownMissing(_ url: URL) -> Bool
}

extension FileAccessProvider {
    public func isKnownMissing(_ url: URL) -> Bool { false }
}

/// Unsandboxed access. Reads are plain `FileManager` calls.
public struct DirectFileAccess: FileAccessProvider {
    public init() {}

    public func hasAccess(to url: URL) -> Bool {
        FileManager.default.isReadableFile(atPath: url.path)
    }

    public func isKnownMissing(_ url: URL) -> Bool {
        !FileManager.default.fileExists(atPath: url.path)
    }

    public func withAccess<T>(to url: URL, _ body: (URL) throws -> T) throws -> T {
        try body(url)
    }
}

public enum FileAccessError: LocalizedError, Equatable {
    case noBookmark(URL)
    case bookmarkUnresolvable(URL)
    case accessDenied(URL)

    /// Localised against the app bundle, like everything else in BelayKit that
    /// can reach a person: this text lands in the panel's warning row, and an
    /// English sentence in an otherwise Russian window is the bug.
    public var errorDescription: String? {
        switch self {
        case .noBookmark(let url):
            return String(
                localized: "Belay has not been granted access to \(url.lastPathComponent) yet.",
                bundle: .main)
        case .bookmarkUnresolvable(let url):
            return String(
                localized:
                    "Belay's saved permission for \(url.lastPathComponent) is no longer valid.",
                bundle: .main)
        case .accessDenied(let url):
            return String(
                localized: "macOS denied Belay access to \(url.lastPathComponent).", bundle: .main)
        }
    }
}
