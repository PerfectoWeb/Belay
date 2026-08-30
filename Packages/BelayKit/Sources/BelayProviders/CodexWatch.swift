import BelayCore
import Foundation

/// One Codex rollout the provider is following.
struct CodexWatch: Sendable {
    let id: SessionID
    var cursor: TranscriptCursor
    /// When the file was last seen to change. Drives the no-growth idle rule.
    var lastWriteAt: Date
    /// The largest `token_count` total the rollout has reported. Codex writes
    /// cumulative totals, so the newest is the truth and it only grows.
    var tokens = 0
    var workspace: String?
    /// The last activity yielded, so `.idle` is not repeated every sweep while
    /// `.working` stays a heartbeat.
    var reported: SessionActivity?
    /// Whether the UI has ever heard of this session: only an announced session
    /// gets an announced ending, or a burst of deleted old rollouts becomes a
    /// burst of phantom `.ended` rows.
    var announced = false
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
