import BelayCore
import Foundation

/// The only six fields Belay takes out of a hook POST body.
///
/// This struct is the privacy boundary of the whole module. `UserPromptSubmit`
/// bodies carry the user's entire prompt and `PostToolUse` bodies carry tool
/// output (docs/DISCOVERY §3.2). Neither has a `CodingKey` here, so neither is
/// ever decoded into a Belay value, stored in a property, or passed to a logger.
/// PRD R9 makes that a product constraint rather than a preference: every field
/// here must be an identifier, a name or a count — never content — and the raw
/// body goes to nothing else.
///
/// The two beyond the original four hold to that line: `toolName` is the name
/// of a tool, not its input, and `backgroundTasks` is how many entries the
/// `background_tasks` array had — the entries themselves are never decoded.
///
/// It is deliberately not `public`. Nothing outside the bridge should be able to
/// construct or hold a value that came from a prompt-bearing payload.
struct HookEnvelope: Equatable {
    let sessionID: String
    let eventName: String
    let cwd: String?
    let transcriptPath: String?
    let toolName: String?
    let backgroundTasks: Int?

    init(
        sessionID: String,
        eventName: String,
        cwd: String?,
        transcriptPath: String?,
        toolName: String? = nil,
        backgroundTasks: Int? = nil
    ) {
        self.sessionID = sessionID
        self.eventName = eventName
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.toolName = toolName
        self.backgroundTasks = backgroundTasks
    }
}

extension HookEnvelope: Decodable {
    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case eventName = "hook_event_name"
        case cwd
        case transcriptPath = "transcript_path"
        case toolName = "tool_name"
        case backgroundTasks = "background_tasks"
    }

    /// Decodes an array element without reading any of it: the count is the
    /// only thing `background_tasks` is allowed to contribute.
    private struct Counted: Decodable {
        init(from decoder: Decoder) throws {}
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        eventName = try container.decode(String.self, forKey: .eventName)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        transcriptPath = try container.decodeIfPresent(String.self, forKey: .transcriptPath)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        // Tolerant on purpose: a CLI that turns this into a count or an object
        // one day must not take the whole envelope down with it.
        backgroundTasks =
            (try? container.decodeIfPresent([Counted].self, forKey: .backgroundTasks))?
            .count
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

    /// `nil` for an event Belay does not register or does not recognise: a newer
    /// CLI firing something unknown must be ignored, never guessed at.
    ///
    /// The provider comes from the caller because the body cannot carry it:
    /// Codex copied Claude Code's hook payload down to the field names, so the
    /// only thing that knows who is posting is the URL the installer wrote.
    func signal(at now: Date, provider: ProviderID = .claudeCode) -> ActivitySignal? {
        guard let event, !sessionID.isEmpty else { return nil }
        // SubagentStop trails the turn's own Stop by seconds — cleanup, not
        // work — and one trailing `.working` pins the Mac for the whole exact
        // freshness window. Mid-turn it added nothing either: the parent's
        // heartbeats and the subagents' watched transcripts carry the hold.
        guard event != .subagentStop else { return nil }
        return ActivitySignal(
            provider: provider,
            session: SessionID(sessionID),
            activity: activity(for: event),
            workspace: workspace,
            timestamp: now,
            confidence: .exact)
    }

    /// The payload can overrule the event's default reading, in two cases.
    ///
    /// A `Stop` whose `background_tasks` is not empty is not an ending: the
    /// turn closed, but background agents or shell jobs are still running, and
    /// some of them have no process of their own to find. The count cannot be
    /// re-verified later, so nothing special keeps it alive — if no further
    /// event arrives, the session ages out through the ordinary TTL.
    ///
    /// A `PreToolUse` naming `AskUserQuestion` or `ExitPlanMode` is a question,
    /// not work: the agent is blocked on a human from the moment the tool
    /// starts, not from some later notification.
    private func activity(for event: HookEvent) -> SessionActivity {
        if event == .stop, let backgroundTasks, backgroundTasks > 0 { return .working }
        if event == .preToolUse, let toolName, Self.waitingTools.contains(toolName) {
            return .awaitingUser
        }
        return event.activity
    }

    /// Tools whose start means "a person has to answer now".
    static let waitingTools: Set<String> = ["AskUserQuestion", "ExitPlanMode"]
}
