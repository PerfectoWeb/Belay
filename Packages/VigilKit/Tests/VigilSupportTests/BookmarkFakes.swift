import Foundation

@testable import VigilSupport

/// A stand-in for Foundation's bookmark calls that counts them.
///
/// The real ones cannot run here: a test process has no
/// `com.apple.security.files.bookmarks.app-scope` entitlement, and
/// `startAccessingSecurityScopedResource()` answers `false` for a URL that did
/// not come from a panel. Bookmark bytes are therefore `path#generation`, which
/// is enough to prove a round trip and to tell a renewed encoding from the one
/// it replaced.
///
/// `@unchecked Sendable`, justified: a test double whose fields are only ever
/// touched from the test's own thread, with a lock anyway because the protocol
/// it conforms to is `Sendable`.
final class FakeBookmarks: SecurityScopedBookmarks, @unchecked Sendable {
    struct Refused: Error {}

    private let lock = NSLock()
    private var generation = 0
    private var counts = Counts()
    private var behaviour = Behaviour()

    struct Counts: Equatable {
        var encodes = 0
        var resolves = 0
        var starts = 0
        var stops = 0
        /// Scopes opened and not yet closed. The number that must not drift.
        var outstanding: Int { starts - stops }
    }

    struct Behaviour {
        var resolvesStale = false
        var canResolve = true
        var canEncode = true
        var canStart = true
    }

    var tally: Counts { lock.withLock { counts } }

    func set(_ change: (inout Behaviour) -> Void) {
        lock.withLock { change(&behaviour) }
    }

    func bookmarkData(for url: URL) throws -> Data {
        try lock.withLock {
            counts.encodes += 1
            guard behaviour.canEncode else { throw Refused() }
            generation += 1
            return Data("\(url.standardizedFileURL.path)#\(generation)".utf8)
        }
    }

    func resolve(_ data: Data) throws -> ResolvedBookmark {
        try lock.withLock {
            counts.resolves += 1
            guard behaviour.canResolve else { throw Refused() }
            let encoded = String(bytes: data, encoding: .utf8) ?? ""
            let path = String(encoded.prefix { $0 != "#" })
            return ResolvedBookmark(
                url: URL(fileURLWithPath: path, isDirectory: true),
                isStale: behaviour.resolvesStale)
        }
    }

    func startAccessing(_ url: URL) -> Bool {
        lock.withLock {
            guard behaviour.canStart else { return false }
            counts.starts += 1
            return true
        }
    }

    func stopAccessing(_ url: URL) {
        lock.withLock { counts.stops += 1 }
    }
}

/// Bookmark bytes in memory. The real store is `UserDefaults`, and a suite that
/// used it would either clobber a real grant or quietly depend on one.
final class MemoryBookmarkStore: BookmarkStore, @unchecked Sendable {
    private let lock = NSLock()
    private var contents: [String: Data] = [:]
    private var writes = 0

    var writeCount: Int { lock.withLock { writes } }

    func data(forKey key: String) -> Data? {
        lock.withLock { contents[key] }
    }

    func setData(_ data: Data?, forKey key: String) {
        lock.withLock {
            writes += 1
            contents[key] = data
        }
    }
}
