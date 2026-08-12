import BelayCore

/// The Claude Code hook events Belay registers, and what each one says about a
/// session.
///
/// The installed CLI fires 31 events (docs/DISCOVERY §3.3); this is the subset
/// that can change what Belay believes, and registering only these keeps the
/// user's agent from making round trips that would tell us nothing new.
///
/// Two entries in here are load bearing and easy to get wrong. `StopFailure`
/// means the turn did **not** end — mapping it like `Stop` would release the
/// assertion mid-run. `PermissionRequest` and `Elicitation` are the precise
/// forms of `Notification`, which is a catch-all that also fires for messages
/// nobody is blocked on; `Notification` stays mapped for older CLI versions.
public enum HookEvent: String, CaseIterable, Sendable {
    case sessionStart = "SessionStart"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case postToolBatch = "PostToolBatch"
    case subagentStart = "SubagentStart"
    case subagentStop = "SubagentStop"
    case permissionRequest = "PermissionRequest"
    case elicitation = "Elicitation"
    case elicitationResult = "ElicitationResult"
    case notification = "Notification"
    case stop = "Stop"
    case stopFailure = "StopFailure"
    case sessionEnd = "SessionEnd"

    public var activity: SessionActivity {
        switch self {
        case .sessionStart, .stop:
            return .idle
        case .permissionRequest, .elicitation, .notification:
            return .awaitingUser
        case .sessionEnd:
            return .ended
        case .userPromptSubmit, .preToolUse, .postToolUse, .postToolBatch, .subagentStart,
            .subagentStop, .elicitationResult, .stopFailure:
            return .working
        }
    }

    /// Only tool-scoped events take a `matcher`. Writing one anywhere else is at
    /// best ignored and at worst a schema error in the user's settings file.
    public var isToolScoped: Bool {
        switch self {
        case .preToolUse, .postToolUse, .permissionRequest:
            return true
        default:
            return false
        }
    }
}
