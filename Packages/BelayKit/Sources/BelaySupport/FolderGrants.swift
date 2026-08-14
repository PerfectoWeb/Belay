import CryptoKit
import Foundation

/// Access to the folders the user picked for a generic target, one
/// security-scoped bookmark each.
///
/// `BookmarkFileAccess` is a grant for one directory, which is right for
/// `~/.claude` because there is exactly one of those. A generic target's folder
/// is different: there can be several, the user chooses them at any time, and
/// they are anywhere on the disk. This holds one `BookmarkFileAccess` per
/// folder and answers for whichever of them covers the URL being read.
///
/// Why it had to exist. Before this, the sandboxed build handed the generic
/// provider the same access object the Claude Code provider uses, which is a
/// grant for `~/.claude` and nothing else. A folder picked anywhere else failed
/// its `hasAccess` check straight away, so the target reported "needs setup"
/// and never watched anything. The open panel gave the process a scope for the
/// folder, but nobody took a bookmark, so even that much was gone at the next
/// launch. In the direct build none of it showed, because there the access
/// object reads the disk outright.
public final class FolderGrants: FileAccessProvider, @unchecked Sendable {
    /// Where the list of remembered folders lives. The bookmarks themselves are
    /// one key each, beside it.
    public static let indexKey = "BelayWatchedFolders"

    private let store: BookmarkStore
    private let bookmarks: SecurityScopedBookmarks
    private let lock = NSLock()
    /// One grant per folder, keyed by its standardised path.
    private var grants: [String: BookmarkFileAccess] = [:]

    public init(
        store: BookmarkStore = DefaultsBookmarkStore(),
        bookmarks: SecurityScopedBookmarks = AppScopedBookmarks()
    ) {
        self.store = store
        self.bookmarks = bookmarks
        restore()
    }

    // MARK: - Remembering

    /// Records a folder the user picked, so the next launch can read it too.
    ///
    /// Called from the open panel's completion, where the process already has a
    /// transient scope for the URL. That scope is what makes the bookmark
    /// possible; taking it later, from a URL that came out of defaults, does
    /// not work and fails in a way that looks like the folder disappearing.
    public func remember(_ url: URL) throws {
        let folder = url.standardizedFileURL
        let access = BookmarkFileAccess(
            root: folder, key: Self.key(for: folder), store: store, bookmarks: bookmarks)
        try access.grant(folder)
        lock.withLock { grants[folder.path] = access }
        index(adding: folder)
    }

    /// Forgets one folder, and the bookmark with it. A target the user deleted
    /// should not leave a grant behind that outlives it.
    public func forget(_ url: URL) {
        let folder = url.standardizedFileURL
        let access = lock.withLock { grants.removeValue(forKey: folder.path) }
        access?.releaseRootScope()
        store.setData(nil, forKey: Self.key(for: folder))
        index(removing: folder)
    }

    /// Which folders this holds a grant for. Ordered, so a test can assert on it.
    public var remembered: [URL] {
        lock.withLock { grants.keys.sorted().map { URL(fileURLWithPath: $0, isDirectory: true) } }
    }

    /// Drops every sustained scope. The counterpart of `ClaudeAccess.relinquish`,
    /// called on the way out so this process leaves none open.
    public func relinquish() {
        for access in lock.withLock({ Array(grants.values) }) { access.releaseRootScope() }
    }

    // MARK: - Reading

    public func hasAccess(to url: URL) -> Bool {
        guard let access = grant(covering: url) else {
            // No grant of ours covers it, so the sandbox is the authority and a
            // plain readability check asks it directly. Outside the sandbox
            // that is the whole answer.
            return FileManager.default.isReadableFile(atPath: url.path)
        }
        return access.hasAccess(to: url)
    }

    public func withAccess<T>(to url: URL, _ body: (URL) throws -> T) throws -> T {
        guard let access = grant(covering: url) else { return try body(url) }
        return try access.withAccess(to: url, body)
    }

    // MARK: - Bookkeeping

    private func grant(covering url: URL) -> BookmarkFileAccess? {
        lock.withLock {
            // Longest path first, so a folder nested inside another granted
            // folder is read through its own grant rather than its parent's.
            grants
                .filter { BookmarkFileAccess.covers(URL(fileURLWithPath: $0.key), url) }
                .max { $0.key.count < $1.key.count }?
                .value
        }
    }

    /// Rebuilds the grants named in the index. A folder whose bookmark no longer
    /// resolves stays in the index: the target is still configured, and the
    /// provider's own "needs setup" is the right place for the user to hear
    /// about it, not a silent deletion here.
    private func restore() {
        for folder in indexed() {
            let access = BookmarkFileAccess(
                root: folder, key: Self.key(for: folder), store: store, bookmarks: bookmarks)
            lock.withLock { grants[folder.path] = access }
        }
    }

    private func indexed() -> [URL] {
        guard let data = store.data(forKey: Self.indexKey),
            let paths = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return paths.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private func write(_ folders: [URL]) {
        let paths = folders.map(\.standardizedFileURL.path)
        store.setData(try? JSONEncoder().encode(paths), forKey: Self.indexKey)
    }

    private func index(adding folder: URL) {
        var folders = indexed()
        guard !folders.contains(where: { $0.path == folder.path }) else { return }
        folders.append(folder)
        write(folders)
    }

    private func index(removing folder: URL) {
        write(indexed().filter { $0.path != folder.path })
    }

    /// A defaults key derived from the path rather than the path itself.
    ///
    /// A user's folder name can be anything, including characters that make a
    /// poor key and a name they would not expect to find written down in a
    /// preferences file. The digest is stable across launches, which is all a
    /// key has to be.
    static func key(for folder: URL) -> String {
        let digest = SHA256.hash(data: Data(folder.standardizedFileURL.path.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "BelayWatchedFolderBookmark.\(hex.prefix(16))"
    }
}
