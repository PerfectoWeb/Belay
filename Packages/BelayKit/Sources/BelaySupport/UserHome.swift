import Foundation

/// The account's real home directory, not the sandbox container.
///
/// `NSHomeDirectory()` and `FileManager.homeDirectoryForCurrentUser` both
/// answer with the container path inside the App Sandbox, so the MAS build
/// would look for `~/.claude` beneath its own container, find nothing, and
/// report that Claude Code is not installed. `getpwuid` reads the account
/// record and is permitted under the sandbox; it is the only way to the real
/// path, and it is why the bookmark has something to point at.
public enum UserHome {
    public static var real: URL {
        guard let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
    }
}
