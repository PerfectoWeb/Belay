import Foundation
import VigilCore

/// The only four fields Vigil takes out of a hook POST body.
///
/// This struct is the privacy boundary of the whole module. `UserPromptSubmit`
/// bodies carry the user's entire prompt and `PostToolUse` bodies carry tool
/// output (docs/DISCOVERY §3.2). Neither has a `CodingKey` here, so neither is
/// ever decoded into a Vigil value, stored in a property, or passed to a logger.
/// PRD R9 makes that a product constraint rather than a preference: do not add
/// a field to this struct, and do not hand the raw body to anything else.
///
/// It is deliberately not `public`. Nothing outside the bridge should be able to
/// construct or hold a value that came from a prompt-bearing payload.
struct HookEnvelope: Decodable, Equatable {
    let sessionID: String
    let eventName: String
    let cwd: String?
    let transcriptPath: String?

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case eventName = "hook_event_name"
        case cwd
        case transcriptPath = "transcript_path"
    }
}

extension HookEnvelope {
    var event: HookEvent? { HookEvent(rawValue: eventName) }

    /// The project folder name, which is what the panel shows. The encoded
    /// directory name under `~/.claude/projects` is lossy, so `cwd` is the only
    /// honest source for it (docs/DISCOVERY §1).
    var workspace: String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? nil : name
    }

    /// `nil` for an event Vigil does not register or does not recognise: a newer
    /// CLI firing something unknown must be ignored, never guessed at.
    func signal(at now: Date) -> ActivitySignal? {
        guard let event, !sessionID.isEmpty else { return nil }
        return ActivitySignal(
            provider: .claudeCode,
            session: SessionID(sessionID),
            activity: event.activity,
            workspace: workspace,
            timestamp: now,
            confidence: .exact)
    }
}
