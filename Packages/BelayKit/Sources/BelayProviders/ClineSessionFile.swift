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

/// One followed session — a root with its state file, or a teammate, whose
/// whole record is a growing messages file inside its parent's directory.
struct ClineWatch {
    let id: SessionID
    /// The root's own state file; a teammate carries its *parent's*, because
    /// a teammate has no status of its own — its lifecycle rides the parent.
    let stateURL: URL
    let messagesURL: URL
    /// Set for a teammate; the UI nests it under this session.
    var parent: SessionID?
    /// The teammate's agent name ("hardening-agent"), for display.
    var kind: String?
    var workspace: String?
    var lastWriteAt: Date
    /// The messages file's last seen size; growth while running is the
    /// heartbeat that keeps the idle sweep at bay.
    var messagesBytes: UInt64
    var reported: SessionActivity?
    /// Whether the UI has ever heard of this session: only an announced
    /// session gets an announced ending.
    var announced = false

    init(
        id: SessionID,
        stateURL: URL,
        parent: SessionID? = nil,
        kind: String? = nil,
        workspace: String?,
        lastWriteAt: Date,
        messagesBytes: UInt64,
        reported: SessionActivity?,
        messagesURL: URL? = nil
    ) {
        self.id = id
        self.stateURL = stateURL
        self.parent = parent
        self.kind = kind
        self.workspace = workspace
        self.lastWriteAt = lastWriteAt
        self.messagesBytes = messagesBytes
        self.reported = reported
        self.messagesURL =
            messagesURL
            ?? stateURL.deletingLastPathComponent()
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
        // Both sides through the same resolver, not only the root. FSEvents
        // hands back `/private`-resolved paths while Foundation's resolver
        // strips `/private` back off (`/private/var/…` → `/var/…`), so a
        // custom root under /tmp or /var matched raw-against-resolved failed
        // every prefix check and the provider saw nothing (caught live on a
        // watched-folder demo root; the default `~/.cline` hid it).
        let rootPath = root.resolvingSymlinksInPath().path + "/"
        let changed = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard let below = remainder(of: changed, under: rootPath) else { return nil }
        guard let id = below.split(separator: "/").first, !id.isEmpty else { return nil }
        return String(id)
    }

    /// The path's tail below the root, matched with the `/private` wrinkle in
    /// mind. The resolver strips `/private` only from paths that still exist,
    /// so the *deletion* event for `<id>.json` — the one that ends a session —
    /// keeps the prefix its living siblings lost, fails the plain check, and
    /// the row never ends. Stripping it by hand when the rest matches the root
    /// is exactly what the resolver would have done had the file survived.
    private static func remainder(of path: String, under root: String) -> Substring? {
        if path.hasPrefix(root) { return path.dropFirst(root.count) }
        let prefix = "/private"
        guard path.hasPrefix(prefix + "/") else { return nil }
        let stripped = path.dropFirst(prefix.count)
        guard stripped.hasPrefix(root) else { return nil }
        return stripped.dropFirst(root.count)
    }

    /// A teammate's file inside a session directory: `<agent>__<suffix>.messages.json`
    /// where the stem is not the session's own. Returns the stem and the
    /// agent name in front of the `__`.
    static func teammate(of path: String, sessionID: String) -> (stem: String, agent: String)? {
        let name = (path as NSString).lastPathComponent
        let suffix = ".messages.json"
        guard name.hasSuffix(suffix) else { return nil }
        let stem = String(name.dropLast(suffix.count))
        guard stem != sessionID, !stem.isEmpty else { return nil }
        let agent = stem.range(of: "__").map { String(stem[..<$0.lowerBound]) } ?? stem
        return (stem, agent.isEmpty ? stem : agent)
    }

    struct TeammateFile {
        let stem: String
        let agent: String
        let url: URL
    }

    static func teammateFiles(
        inSession sessionID: String, under root: URL, access: FileAccessProvider
    ) -> [TeammateFile] {
        let directory = root.appendingPathComponent(sessionID, isDirectory: true)
        let contents: [URL]? = try? access.withAccess(to: directory) { url in
            (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        }
        return (contents ?? []).compactMap { url in
            guard let mate = teammate(of: url.path, sessionID: sessionID) else { return nil }
            return TeammateFile(stem: mate.stem, agent: mate.agent, url: url)
        }
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
