import BelayCore
import BelaySupport
import Foundation

/// Where a transcript sits in `~/.claude/projects`, and therefore who owns it.
///
/// Found empirically (docs/DISCOVERY §1.2). Three layouts exist:
///
/// ```
/// <project>/<session>.jsonl                                      a real session
/// <project>/<session>/subagents/agent-<id>.jsonl                 a Task subagent
/// <project>/<session>/subagents/workflows/<run>/agent-<id>.jsonl a workflow agent
/// ```
///
/// The component immediately before `subagents` is the parent session's UUID,
/// which is the whole answer to "whose agent is this" — and it agrees with the
/// `sessionId` field carried inside every subagent record, so the cheap
/// structural read needs no file open to confirm it.
///
/// Getting this wrong was visible in the UI: `workspaceName` used to take the
/// containing folder's last dash-separated segment, so fifty-four workflow
/// agents under `wf_60f0c106-9d2` all showed up as separate sessions called
/// "9d2", crowding the real one off the list.
struct TranscriptLocation: Equatable {
    /// The parent session, when this transcript belongs to a subagent.
    var parent: SessionID?
    /// The `<project>` directory — flattened cwd, never to be reversed into a
    /// path (docs/DISCOVERY §1).
    var projectDirectory: String?

    static let marker = "subagents"

    init(transcript: URL) {
        let components = transcript.deletingLastPathComponent().pathComponents
        guard let marker = components.lastIndex(of: Self.marker), marker >= 1 else {
            projectDirectory = components.last
            return
        }
        parent = SessionID(components[marker - 1])
        projectDirectory = marker >= 2 ? components[marker - 2] : nil
    }

    var isSubagent: Bool { parent != nil }

    /// Whether this file is an agent's conversation at all.
    ///
    /// The workflow runner writes a `journal.jsonl` in the same folder as the
    /// agents it spawned. It grows while the run does, so left alone it becomes
    /// a phantom session row called "journal" that nobody started.
    static func isAgentTranscript(_ transcript: URL) -> Bool {
        guard TranscriptLocation(transcript: transcript).isSubagent else { return true }
        return transcript.lastPathComponent.hasPrefix("agent-")
    }
}

extension TranscriptLocation {
    /// The agent's configured type, from the `.meta.json` written beside the
    /// transcript — `general-purpose`, `workflow-subagent`, or whatever the user
    /// named their own agent.
    ///
    /// That sidecar also holds a one-line `description` of the task, which is
    /// deliberately **not** read: it is a summary of the user's prompt, and the
    /// About pane promises those are never touched. A menu bar panel is on
    /// screen during screen shares.
    static func kind(of transcript: URL, access: FileAccessProvider) -> String? {
        let sidecar = transcript.deletingPathExtension().appendingPathExtension("meta.json")
        guard let data = try? access.withAccess(to: sidecar, { try Data(contentsOf: $0) }),
            let meta = try? JSONDecoder().decode(AgentMeta.self, from: data),
            let kind = meta.agentType, !kind.isEmpty
        else { return nil }
        return kind
    }

    private struct AgentMeta: Decodable {
        let agentType: String?
    }
}
