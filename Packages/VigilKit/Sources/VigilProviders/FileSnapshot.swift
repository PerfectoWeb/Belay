import Foundation

/// One `stat(2)` call's worth of what the transcript watcher needs.
///
/// Size, inode and mtime come from the same syscall so a cursor can never
/// compare a size taken at one moment against an inode taken at another — that
/// race is exactly how a rotated transcript gets read from the wrong offset.
struct FileSnapshot: Sendable, Equatable {
    let size: UInt64
    let inode: UInt64
    let modified: Date

    init?(path: String) {
        var info = stat()
        guard stat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        size = UInt64(max(0, info.st_size))
        inode = UInt64(info.st_ino)
        modified = Date(
            timeIntervalSince1970: Double(info.st_mtimespec.tv_sec)
                + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000)
    }

    init?(url: URL) {
        self.init(path: url.path)
    }
}
