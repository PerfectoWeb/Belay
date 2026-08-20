import BelayCore
import Foundation

/// One Codex rollout the provider is following.
struct CodexWatch: Sendable {
    let id: SessionID
    var cursor: TranscriptCursor
    /// When the file was last seen to change. Drives the no-growth idle rule.
    var lastWriteAt: Date
    var workspace: String?
    /// The last activity yielded, so `.idle` is not repeated every sweep while
    /// `.working` stays a heartbeat.
    var reported: SessionActivity?
    /// The last marker seen was `task_started` with no `task_complete` after
    /// it: the model owes an answer, and silence gets the longer horizon.
    var turnOpen = false

    init(id: SessionID, url: URL, lastWriteAt: Date, workspace: String?) {
        self.id = id
        self.cursor = TranscriptCursor(url: url)
        self.lastWriteAt = lastWriteAt
        self.workspace = workspace
    }

    var url: URL { cursor.url }
}
