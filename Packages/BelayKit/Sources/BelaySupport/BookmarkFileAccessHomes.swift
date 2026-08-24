import Foundation

/// The one-per-agent factories. Each grant is a separate permission under its
/// own defaults key, and none may ever overwrite another's bookmark. Beside
/// `BookmarkFileAccess` for the file-length rule.
extension BookmarkFileAccess {
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

    /// `~/.codex`.
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

    /// `~/.cline`.
    public static func clineHome(
        home: URL = UserHome.real,
        store: BookmarkStore = DefaultsBookmarkStore(),
        bookmarks: SecurityScopedBookmarks = AppScopedBookmarks()
    ) -> BookmarkFileAccess {
        BookmarkFileAccess(
            root: home.appendingPathComponent(".cline", isDirectory: true),
            key: "BelayClineFolderBookmark",
            store: store,
            bookmarks: bookmarks)
    }

    /// `~/.copilot`.
    public static func copilotHome(
        home: URL = UserHome.real,
        store: BookmarkStore = DefaultsBookmarkStore(),
        bookmarks: SecurityScopedBookmarks = AppScopedBookmarks()
    ) -> BookmarkFileAccess {
        BookmarkFileAccess(
            root: home.appendingPathComponent(".copilot", isDirectory: true),
            key: "BelayCopilotFolderBookmark",
            store: store,
            bookmarks: bookmarks)
    }
}
