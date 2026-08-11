import Foundation
import Testing

@testable import VigilSupport

/// What can be proved about a security-scoped grant without a sandbox: the
/// bookmark round trip, the staleness rule, and the balance of every scope this
/// class opens. What cannot is written down in `BLOCKERS.md` B8.
@Suite final class BookmarkFileAccessTests: Sendable {
    private let bookmarks = FakeBookmarks()
    private let store = MemoryBookmarkStore()
    private let root: URL
    private let transcript: URL

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("vigil-bookmark-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(".claude", isDirectory: true)
        transcript = root.appendingPathComponent("projects/session.jsonl")
        try FileManager.default.createDirectory(
            at: transcript.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}\n".utf8).write(to: transcript)
    }

    deinit {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    private func access() -> BookmarkFileAccess {
        BookmarkFileAccess(root: root, key: "test", store: store, bookmarks: bookmarks)
    }

    // MARK: - The round trip

    @Test func aGrantSurvivesEncodeResolveAndTheNextLaunch() throws {
        let first = access()
        #expect(first.isGranted == false)

        try first.grant(root)
        #expect(first.isGranted)
        #expect(store.data(forKey: "test") != nil)
        first.releaseRootScope()

        // A second instance is the next launch: it has only the bytes.
        let relaunched = access()
        #expect(relaunched.isGranted)
        #expect(relaunched.hasAccess(to: transcript))
        let read = try relaunched.withAccess(to: transcript) { try Data(contentsOf: $0) }
        #expect(read.isEmpty == false)
        relaunched.releaseRootScope()
    }

    /// Foundation asking for a re-encoding is housekeeping, not a revocation.
    /// Dropping the grant would send the user back through the panel for it.
    @Test func aStaleBookmarkIsRenewedRatherThanDropped() throws {
        try access().grant(root)
        let original = store.data(forKey: "test")
        bookmarks.set { $0.resolvesStale = true }

        let relaunched = access()

        #expect(relaunched.isGranted)
        #expect(store.data(forKey: "test") != nil)
        #expect(store.data(forKey: "test") != original, "the stale bytes were kept as they were")
        relaunched.releaseRootScope()
    }

    /// A renewal that fails is not a reason to lose a bookmark that still
    /// resolves.
    @Test func aFailedRenewalKeepsTheBookmarkThatStillWorks() throws {
        try access().grant(root)
        let original = store.data(forKey: "test")
        bookmarks.set {
            $0.resolvesStale = true
            $0.canEncode = false
        }

        let relaunched = access()

        #expect(relaunched.isGranted)
        #expect(store.data(forKey: "test") == original)
        relaunched.releaseRootScope()
    }

    // MARK: - Balance

    @Test func accessIsBalancedWhenTheBodyThrows() throws {
        let access = access()
        try access.grant(root)
        let before = bookmarks.tally

        #expect(throws: Refusal.self) {
            try access.withAccess(to: transcript) { _ in throw Refusal() }
        }

        let after = bookmarks.tally
        #expect(after.starts == before.starts + 1)
        #expect(after.stops == before.stops + 1)
        #expect(after.outstanding == before.outstanding)
        access.releaseRootScope()
        #expect(bookmarks.tally.outstanding == 0)
    }

    @Test func accessIsBalancedOnTheOrdinaryPath() throws {
        let access = access()
        try access.grant(root)
        let before = bookmarks.tally

        for _ in 0..<8 {
            _ = try access.withAccess(to: transcript) { $0.lastPathComponent }
            _ = access.hasAccess(to: transcript)
        }

        #expect(bookmarks.tally.outstanding == before.outstanding)
        access.releaseRootScope()
        #expect(bookmarks.tally.outstanding == 0)
    }

    /// A scope that will not open is an error the caller sees, not a silent
    /// half-open one.
    @Test func aRefusedScopeThrowsAndOpensNothing() throws {
        let access = access()
        try access.grant(root)
        access.releaseRootScope()
        bookmarks.set { $0.canStart = false }

        #expect(throws: FileAccessError.self) {
            try access.withAccess(to: transcript) { $0 }
        }
        #expect(access.hasAccess(to: transcript) == false)
        #expect(bookmarks.tally.outstanding == 0)
    }

    // MARK: - Honest answers

    @Test func hasAccessIsFalseWithNoBookmarkAndCreatesNone() {
        let access = access()

        #expect(access.hasAccess(to: transcript) == false)
        #expect(access.hasAccess(to: root) == false)

        #expect(store.data(forKey: "test") == nil)
        #expect(store.writeCount == 0)
        #expect(bookmarks.tally == FakeBookmarks.Counts())
    }

    @Test func aReadWithNoGrantSaysWhichFolderIsMissing() {
        let access = access()

        #expect(throws: FileAccessError.noBookmark(root)) {
            try access.withAccess(to: transcript) { $0 }
        }
    }

    /// "Granted once, broken now" and "never granted" read the same to the
    /// filesystem and have to read differently to the user.
    @Test func aBookmarkThatWillNotResolveSaysSoAndIsKept() throws {
        try access().grant(root)
        let saved = store.data(forKey: "test")
        bookmarks.set { $0.canResolve = false }

        let relaunched = access()

        #expect(relaunched.isGranted == false)
        #expect(throws: FileAccessError.bookmarkUnresolvable(root)) {
            try relaunched.withAccess(to: transcript) { $0 }
        }
        #expect(store.data(forKey: "test") == saved, "the evidence of a past grant was deleted")
    }

    /// A path this grant is not about — a generic provider's watched folder —
    /// is passed straight through for the sandbox itself to judge.
    @Test func pathsOutsideTheGrantAreNotItsBusiness() throws {
        let access = access()
        let elsewhere = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("vigil-elsewhere-\(UUID().uuidString)")
        try Data("x".utf8).write(to: elsewhere)
        defer { try? FileManager.default.removeItem(at: elsewhere) }

        let name = try access.withAccess(to: elsewhere) { $0.lastPathComponent }

        #expect(name == elsewhere.lastPathComponent)
        #expect(access.hasAccess(to: elsewhere))
        #expect(bookmarks.tally.starts == 0)
    }

    @Test func containmentIsByPathComponentNotByPrefix() {
        #expect(BookmarkFileAccess.covers(root, root))
        #expect(BookmarkFileAccess.covers(root, transcript))
        #expect(BookmarkFileAccess.covers(root, root.deletingLastPathComponent()) == false)
        let sibling = root.deletingLastPathComponent().appendingPathComponent(".claude-backup")
        #expect(BookmarkFileAccess.covers(root, sibling) == false)
    }
}

private struct Refusal: Error {}
