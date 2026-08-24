import BelayCore
import BelaySupport
import Foundation

/// What one Cline session says about itself, read from
/// `~/.cline/data/sessions/<id>/<id>.json`.
///
/// The state file carries the user's whole prompt and the session title, so
/// this type is the privacy boundary the way `TranscriptRecord` is for Claude
/// Code (PRD R9): only status, paths and the pid are declared as coding keys,
/// so nothing else is ever decoded into a Belay value. The sibling
/// `<id>.messages.json` holds the conversation itself and is never opened —
/// its file size is the only thing Belay reads off it.
struct ClineSessionState: Decodable, Equatable {
    enum Status: String {
        case running
        case idle
        case completed
        case cancelled
        case failed

        /// `running` is a turn; `idle` is an interactive session waiting for
        /// its person; the last three are a session that is over.
        var activity: SessionActivity {
            switch self {
            case .running: return .working
            case .idle: return .idle
            case .completed, .cancelled, .failed: return .ended
            }
        }
    }

    let sessionID: String
    let status: String
    let workspaceRoot: String?
    let cwd: String?

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case status
        case workspaceRoot = "workspace_root"
        case cwd
    }

    /// `nil` for a value this build has never seen; the caller keeps its last
    /// belief rather than guessing what a future Cline means.
    var knownStatus: Status? { Status(rawValue: status) }

    /// The project folder name, for the panel.
    var workspace: String? {
        let path = workspaceRoot ?? cwd
        guard let path, !path.isEmpty else { return nil }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? nil : name
    }

    static func load(from url: URL, access: FileAccessProvider) -> ClineSessionState? {
        let data: Data?? = try? access.withAccess(to: url) { try? Data(contentsOf: $0) }
        guard case .some(.some(let bytes)) = data else { return nil }
        return try? JSONDecoder().decode(ClineSessionState.self, from: bytes)
    }
}

/// One followed session: where its two files live and what was last believed.
struct ClineWatch {
    let id: SessionID
    let stateURL: URL
    var workspace: String?
    var lastWriteAt: Date
    /// The messages file's last seen size; growth while running is the
    /// heartbeat that keeps the idle sweep at bay.
    var messagesBytes: UInt64
    var reported: SessionActivity?
    /// Whether the UI has ever heard of this session: only an announced
    /// session gets an announced ending.
    var announced = false

    var messagesURL: URL {
        stateURL.deletingLastPathComponent()
            .appendingPathComponent(stateURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("messages.json")
    }
}

/// Where sessions live on disk and how their paths spell the session id.
enum ClineSessions {
    /// `<root>/<id>/<id>.json`; anything else under the root is not a session
    /// state file.
    static func stateURL(id: String, under root: URL) -> URL {
        root.appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("\(id).json")
    }

    /// The session a changed path belongs to, or `nil` for a path outside the
    /// root. FSEvents hands over anything under the tree; the id is the first
    /// component below the root.
    static func sessionID(of path: String, under root: URL) -> String? {
        let rootPath = root.standardizedFileURL.path + "/"
        guard path.hasPrefix(rootPath) else { return nil }
        let below = path.dropFirst(rootPath.count)
        guard let id = below.split(separator: "/").first, !id.isEmpty else { return nil }
        return String(id)
    }

    static func sessionIDs(under root: URL, access: FileAccessProvider) -> [String] {
        let contents: [URL]? = try? access.withAccess(to: root) { url in
            (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        }
        return (contents ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
    }
}
