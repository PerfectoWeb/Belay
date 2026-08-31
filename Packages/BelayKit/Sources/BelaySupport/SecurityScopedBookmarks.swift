import Foundation

/// One resolved bookmark: where it points, and whether Foundation wants it
/// re-encoded.
public struct ResolvedBookmark: Sendable, Equatable {
    public let url: URL
    /// The bookmark still resolves, but its bytes describe an older layout of
    /// the filesystem. Foundation asks for a fresh encoding; it does not mean
    /// the grant is gone (docs/06).
    public let isStale: Bool

    public init(url: URL, isStale: Bool) {
        self.url = url
        self.isStale = isStale
    }
}

/// The four Foundation calls a security-scoped bookmark needs, behind a
/// protocol.
///
/// Not indirection for its own sake: a unit test process has no
/// `com.apple.security.files.bookmarks.app-scope` entitlement, so it cannot
/// create a real scoped bookmark, and `startAccessingSecurityScopedResource()`
/// answers `false` for any URL that did not come from a panel. What *is*
/// testable is everything around those four calls — which one is made, in what
/// order, and whether every start has its stop — and that is the part that goes
/// wrong (`docs/BLOCKERS.md (git history)` B8).
///
/// The protocol predates `Tests/BelaySandboxTests`, which is hosted by the MAS
/// app and therefore *can* create and resolve a real app-scoped bookmark. The
/// seam is still worth having: the module suites are not sandboxed and never
/// will be, and they are where the ordering is exercised.
public protocol SecurityScopedBookmarks: Sendable {
    func bookmarkData(for url: URL) throws -> Data
    func resolve(_ data: Data) throws -> ResolvedBookmark
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

/// Foundation's own implementation.
///
/// App-scoped on both sides. Creation needs the
/// `com.apple.security.files.bookmarks.app-scope` entitlement the MAS build
/// carries; resolution needs the same option, or the URL comes back stripped of
/// its scope and every read through it is denied with no useful error.
public struct AppScopedBookmarks: SecurityScopedBookmarks {
    public init() {}

    public func bookmarkData(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil)
    }

    public func resolve(_ data: Data) throws -> ResolvedBookmark {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale)
        return ResolvedBookmark(url: url, isStale: isStale)
    }

    public func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    public func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}
