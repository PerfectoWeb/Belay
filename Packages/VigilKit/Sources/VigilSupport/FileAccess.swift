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
}

/// Unsandboxed access. Reads are plain `FileManager` calls.
public struct DirectFileAccess: FileAccessProvider {
    public init() {}

    public func hasAccess(to url: URL) -> Bool {
        FileManager.default.isReadableFile(atPath: url.path)
    }

    public func withAccess<T>(to url: URL, _ body: (URL) throws -> T) throws -> T {
        try body(url)
    }
}

public enum FileAccessError: LocalizedError, Equatable {
    case noBookmark(URL)
    case bookmarkUnresolvable(URL)
    case accessDenied(URL)

    public var errorDescription: String? {
        switch self {
        case .noBookmark(let url):
            return "Vigil has not been granted access to \(url.lastPathComponent) yet."
        case .bookmarkUnresolvable(let url):
            return "Vigil's saved permission for \(url.lastPathComponent) is no longer valid."
        case .accessDenied(let url):
            return "macOS denied Vigil access to \(url.lastPathComponent)."
        }
    }
}
