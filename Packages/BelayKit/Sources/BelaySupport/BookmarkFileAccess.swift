import Foundation

/// `FileAccessProvider` for the sandboxed (Mac App Store) build: one directory,
/// `~/.claude`, reached through an app-scoped security-scoped bookmark that the
/// user hands over in an open panel.
///
/// Three things this has to get right, all of them from `docs/06`:
///
/// - **Balance.** Every read is bracketed by start/stop, including the throwing
///   path. Leaked scoped resources exhaust a per-process limit and detection
///   then dies with no visible cause.
/// - **Staleness.** A stale bookmark still resolves; Foundation only wants it
///   re-encoded. Dropping it would send the user back through the panel for a
///   housekeeping detail, so it is renewed in place and the old bytes are kept
///   if renewing fails.
/// - **Honesty.** `hasAccess(to:)` answers from what is actually resolved and
///   never grants anything as a side effect. Everything above it — the panel,
///   the onboarding button, the provider's `needsSetup` line — is downstream of
///   that one answer.
///
/// `@unchecked Sendable`, justified: the resolved grant is mutable state shared
/// across the provider actors that read through it, and every path in this file
/// touches it under `lock`. An actor cannot stand in, because
/// `FileAccessProvider.withAccess` is synchronous by design — it wraps
/// `FileHandle` reads inside `TranscriptCursor.read`, a synchronous mutating
/// function on the detection hot path.
public final class BookmarkFileAccess: FileAccessProvider, @unchecked Sendable {
    /// The directory this instance is the grant for. A read at or below it
    /// needs the bookmark; anything else is none of its business.
    public let root: URL

    private let key: String
    private let store: BookmarkStore
    private let bookmarks: SecurityScopedBookmarks
    private let lock = NSLock()

    /// The resolved, security-scoped URL. `nil` means no usable grant.
    private var granted: URL?
    /// Distinguishes "never granted" from "granted once and now unresolvable",
    /// which are different sentences to show the user.
    private var hasStoredBookmark = false
    /// The URL of the sustained hold, if one is open. See `holdRootScope`.
    private var held: URL?

    public static let defaultsKey = "BelayClaudeFolderBookmark"

    public init(
        root: URL,
        key: String = BookmarkFileAccess.defaultsKey,
        store: BookmarkStore = DefaultsBookmarkStore(),
        bookmarks: SecurityScopedBookmarks = AppScopedBookmarks()
    ) {
        self.root = root.standardizedFileURL
        self.key = key
        self.store = store
        self.bookmarks = bookmarks
        restore()
    }

    /// `~/.claude`, from the account's real home rather than the container.
    public static func claudeHome(
        home: URL = UserHome.real,
        store: BookmarkStore = DefaultsBookmarkStore(),
        bookmarks: SecurityScopedBookmarks = AppScopedBookmarks()
    ) -> BookmarkFileAccess {
        BookmarkFileAccess(
            root: home.appendingPathComponent(".claude", isDirectory: true),
            store: store,
            bookmarks: bookmarks)
    }

    /// `~/.codex`, under its own defaults key: the two grants are separate
    /// permissions and must never overwrite each other's bookmark.
    public static func codexHome(
        home: URL = UserHome.real,
        store: BookmarkStore = DefaultsBookmarkStore(),
        bookmarks: SecurityScopedBookmarks = AppScopedBookmarks()
    ) -> BookmarkFileAccess {
        BookmarkFileAccess(
            root: home.appendingPathComponent(".codex", isDirectory: true),
            key: "BelayCodexFolderBookmark",
            store: store,
            bookmarks: bookmarks)
    }

    deinit {
        if let held { bookmarks.stopAccessing(held) }
    }

    // MARK: - Granting

    /// Whether a resolved grant covers `root` right now.
    public var isGranted: Bool {
        lock.withLock { granted.map { Self.covers($0, root) } ?? false }
    }

    /// Records the directory the user picked in the open panel.
    ///
    /// The bytes are resolved before they are saved rather than the panel's URL
    /// being trusted: what the next launch will use is the bookmark, so if it
    /// does not come back the user finds out now, while the panel is still in
    /// front of them, instead of on the launch after this one. Nothing is
    /// persisted unless the round trip works.
    public func grant(_ url: URL) throws {
        let data = try bookmarks.bookmarkData(for: url)
        let resolved = try bookmarks.resolve(data)
        store.setData(data, forKey: key)
        releaseRootScope()
        // Not renewing: these bytes were made two lines ago and are the freshest
        // encoding available.
        adopt(resolved, renewingIfStale: false)
    }

    /// Resolves the saved bookmark. Called at construction, which is to say on
    /// launch, and it is the only place staleness can be repaired: renewing
    /// needs the resource open, and by the time a read has failed the app is
    /// already reporting that it cannot see anything.
    public func restore() {
        guard let data = store.data(forKey: key) else { return }
        guard let resolved = try? bookmarks.resolve(data) else {
            // Kept, not deleted. The user is told to grant again; deleting the
            // bytes would also delete the evidence that they ever did.
            lock.withLock {
                hasStoredBookmark = true
                granted = nil
            }
            Log.app.error("saved folder bookmark did not resolve; access has to be granted again")
            return
        }
        adopt(resolved, renewingIfStale: true)
    }

    private func adopt(_ bookmark: ResolvedBookmark, renewingIfStale: Bool) {
        lock.withLock {
            granted = bookmark.url.standardizedFileURL
            hasStoredBookmark = true
        }
        holdRootScope(bookmark.url)
        guard bookmark.isStale, renewingIfStale else { return }
        renew(bookmark.url)
    }

    /// Re-encodes a stale bookmark in place. The hold taken above is what makes
    /// this possible at all: creating bookmark data for a scoped URL requires
    /// the scope to be open.
    private func renew(_ url: URL) {
        guard let fresh = try? bookmarks.bookmarkData(for: url) else {
            Log.app.error("stale bookmark could not be renewed; keeping the one that still resolves")
            return
        }
        store.setData(fresh, forKey: key)
    }

    // MARK: - Reading

    public func hasAccess(to url: URL) -> Bool {
        guard let scope = scope(covering: url) else {
            // Outside the granted tree the sandbox itself is the authority, and
            // a plain readability check asks it directly.
            return isOurs(url) ? false : FileManager.default.isReadableFile(atPath: url.path)
        }
        guard bookmarks.startAccessing(scope) else { return false }
        defer { bookmarks.stopAccessing(scope) }
        return FileManager.default.isReadableFile(atPath: url.path)
    }

    public func withAccess<T>(to url: URL, _ body: (URL) throws -> T) throws -> T {
        guard let scope = scope(covering: url) else {
            guard isOurs(url) else { return try body(url) }
            throw hasBookmark
                ? FileAccessError.bookmarkUnresolvable(root)
                : FileAccessError.noBookmark(root)
        }
        guard bookmarks.startAccessing(scope) else { throw FileAccessError.accessDenied(url) }
        defer { bookmarks.stopAccessing(scope) }
        return try body(url)
    }

    // MARK: - The sustained hold

    /// One hold on the granted directory for as long as this object lives.
    ///
    /// `withAccess` brackets its own reads and that is what keeps the count
    /// balanced, but bracketing alone is not enough to make the app work:
    /// FSEvents watches the granted directory continuously, and the `stat` calls
    /// behind `FileSnapshot` happen outside any bracket, so the scope has to be
    /// open for the whole watch or the sandbox denies both. Exactly one hold,
    /// released before a re-grant and in `deinit`. The per-process limit
    /// `docs/06` warns about is about unbounded leaks; this is one, and it is
    /// accounted for.
    private func holdRootScope(_ url: URL) {
        guard lock.withLock({ held == nil }) else { return }
        guard bookmarks.startAccessing(url) else {
            Log.app.error("the granted folder resolved but its scope would not open")
            return
        }
        lock.withLock { held = url }
    }

    /// Drops the sustained hold. Called on teardown, so a relaunch of the object
    /// graph inside one process does not accumulate holds.
    public func releaseRootScope() {
        guard let open = lock.withLock({ held.take() }) else { return }
        bookmarks.stopAccessing(open)
    }

    // MARK: - Containment

    private var hasBookmark: Bool { lock.withLock { hasStoredBookmark } }

    /// The scoped URL to open for a read of `url`, or nil if we hold no grant
    /// that covers it.
    private func scope(covering url: URL) -> URL? {
        guard let granted = lock.withLock({ granted }) else { return nil }
        return Self.covers(granted, url) ? granted : nil
    }

    /// Whether `url` is inside the directory this grant exists for. Used to
    /// decide whether a missing grant is an error worth reporting or simply
    /// somebody else's path.
    private func isOurs(_ url: URL) -> Bool { Self.covers(root, url) }

    static func covers(_ directory: URL, _ url: URL) -> Bool {
        let parent = directory.standardizedFileURL.path
        let child = url.standardizedFileURL.path
        return child == parent || child.hasPrefix(parent.hasSuffix("/") ? parent : parent + "/")
    }
}

extension Optional {
    /// Reads and clears in one step, so a lock is taken once rather than twice.
    fileprivate mutating func take() -> Wrapped? {
        defer { self = nil }
        return self
    }
}
