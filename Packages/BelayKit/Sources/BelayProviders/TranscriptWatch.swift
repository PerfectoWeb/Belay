import BelayCore
import BelaySupport
import Foundation

/// One transcript the provider is following.
struct TranscriptWatch: Sendable {
    let id: SessionID
    var cursor: TranscriptCursor
    /// When the file was last seen to change. Drives the no-growth idle rule.
    var lastWriteAt: Date
    /// When Tier C last saw a freshly started child process for this session.
    ///
    /// Separate from `lastWriteAt` because it is different evidence: the
    /// transcript has not grown, a tool is simply running without writing. They
    /// were the same field once, and the idle sweep then undid what Tier C had
    /// just reported — the panel flipped working, idle, working every fifteen
    /// seconds for the whole of a long tool call.
    var lastBusyChildAt: Date?
    /// Cumulative `usage` tokens seen in this session's records, normalized
    /// here so every signal carries an absolute total the consumer can only
    /// move forward.
    var tokens = 0
    var workspace: String?
    /// The session this one was spawned by, when it is a subagent.
    var parent: SessionID?
    /// The subagent's configured type, for display.
    var kind: String?
    /// The session's own name, from `~/.claude/sessions/<pid>.json`. Filled in by
    /// Tier C, because the transcript itself does not carry it.
    var name: String?
    /// The last activity yielded for this session, so `.idle` is not repeated
    /// every sweep while `.working` stays a heartbeat.
    var reported: SessionActivity?
    /// Whether the UI has ever heard of this session: only an announced session
    /// gets an announced ending, or a burst of deleted old transcripts becomes
    /// a burst of phantom `.ended` rows.
    var announced = false
    /// The tail record left the model owing the next one — a prompt or tool
    /// result went out, or the CLI wrote an API-error record. Grants the idle
    /// sweep its longer horizon; see `TranscriptClassifier.Verdict`.
    var awaitingAssistant = false

    /// The most recent evidence of any kind that work is happening. What the
    /// idle sweep measures its horizon from.
    var lastEvidenceAt: Date {
        max(lastWriteAt, lastBusyChildAt ?? .distantPast)
    }

    init(
        id: SessionID,
        url: URL,
        lastWriteAt: Date,
        workspace: String?,
        parent: SessionID? = nil,
        kind: String? = nil,
        name: String? = nil
    ) {
        self.id = id
        self.cursor = TranscriptCursor(url: url)
        self.lastWriteAt = lastWriteAt
        self.workspace = workspace
        self.parent = parent
        self.kind = kind
        self.name = name
    }

    /// Everything derivable from where the transcript sits, read once. The
    /// sidecar is written when an agent is spawned and never changes, so there
    /// is no reason to open it again on every signal.
    init(adopting url: URL, id: SessionID, at lastWriteAt: Date, access: FileAccessProvider) {
        let location = TranscriptLocation(transcript: url)
        self.init(
            id: id,
            url: url,
            lastWriteAt: lastWriteAt,
            workspace: Self.workspaceName(for: url),
            parent: location.parent,
            kind: location.isSubagent ? TranscriptLocation.kind(of: url, access: access) : nil)
    }

    var url: URL { cursor.url }
}

extension TranscriptWatch {
    /// The session UUID is the transcript's filename (docs/DISCOVERY §1).
    static func sessionID(for transcript: URL) -> SessionID {
        SessionID(transcript.deletingPathExtension().lastPathComponent)
    }

    /// Display-only fallback for the workspace name.
    ///
    /// The project directory is the cwd with `/` and `.` flattened to `-`, which
    /// is lossy — docs/DISCOVERY §1 is explicit that it must never be reversed
    /// into a path. Taking the last segment is enough for a menu bar row, and
    /// Tier C replaces it with the real `cwd` as soon as it sees the session.
    ///
    /// A subagent's containing folder is `subagents/…`, not the project, so the
    /// project is located structurally rather than by taking the parent folder.
    static func workspaceName(for transcript: URL) -> String? {
        guard let directory = TranscriptLocation(transcript: transcript).projectDirectory else {
            return nil
        }
        let segments = directory.split(separator: "-", omittingEmptySubsequences: true)
        guard let last = segments.last else { return nil }
        return String(last)
    }

    /// Every transcript under a projects root, including subagents. Unreadable
    /// directories are skipped rather than failing the whole sweep.
    ///
    /// Enumerated against the known layout instead of recursing blindly: the
    /// deepest legitimate transcript is four levels down, and a stray symlink in
    /// `~/.claude` should not turn startup into a filesystem walk.
    static func transcripts(under root: URL, access: FileAccessProvider) -> [URL] {
        let projects =
            (try? access.withAccess(to: root) { contents(of: $0) }) ?? []
        return projects.flatMap { project -> [URL] in
            let entries = contents(of: project)
            // `<project>/<session>/subagents[/workflows/<run>]/agent-<id>.jsonl`
            let nested = entries.flatMap { session -> [URL] in
                let subagents = session.appendingPathComponent(TranscriptLocation.marker)
                let direct = contents(of: subagents)
                let runs = contents(of: subagents.appendingPathComponent("workflows"))
                return direct + runs.flatMap { contents(of: $0) }
            }
            return (entries + nested).filter { $0.pathExtension == "jsonl" }
        }
    }

    private static func contents(of directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    }
}
