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
        let reading = activity(for: event)
        return ActivitySignal(
            provider: provider,
            session: SessionID(sessionID),
            activity: reading,
            workspace: workspace,
            timestamp: now,
            confidence: .exact,
            toolCall: edge(for: event, reading: reading),
            tool: event == .preToolUse && reading == .working
                ? Self.category(of: toolName) : nil,
            backgroundTasks: event == .stop ? backgroundTasks ?? 0 : nil)
    }

    /// The badge the panel shows beside "Working". Matched loosely and in
    /// lowercase, because Codex copied Claude Code's payload but not its tool
    /// names, and a future CLI will invent more; an unknown name is still a
    /// tool, never a crash or a blank.
    static func category(of toolName: String?) -> ToolCategory {
        guard let toolName else { return .tool }
        let name = toolName.lowercased()
        if name.hasPrefix("mcp__") { return .tool }
        if name.contains("bash") || name.contains("shell") || name.contains("command") {
            return .command
        }
        let editing = ["edit", "write", "patch", "notebook"]
        if editing.contains(where: name.contains) { return .edit }
        if name.contains("web") || name.contains("fetch") || name.contains("browser") {
            return .web
        }
        if name.contains("read") { return .read }
        if name.contains("grep") || name.contains("glob") || name.contains("search") {
            return .search
        }
        if name.contains("task") || name.contains("agent") { return .subagent }
        return .tool
    }

    /// Which side of a tool call this event is.
    ///
    /// Opening is narrow on purpose: only a `PreToolUse` that means work. The
    /// question tools (`AskUserQuestion`, `ExitPlanMode`) read as
    /// `awaitingUser`, and a human being asked something is not a tool call to
    /// hold the Mac awake for — that state has its own budget.
    ///
    /// Everything else closes, and that breadth is the safety. The tool
    /// returning closes it, and so does the turn stopping, the next prompt
    /// arriving, or a permission being asked for — an agent cannot be inside
    /// two tool calls at once, so any later word from it means the previous one
    /// is over. That is what keeps an interrupted run from holding: whatever
    /// the person does next fires something.
    private func edge(for event: HookEvent, reading: SessionActivity) -> ToolCallEdge {
        if event == .preToolUse, reading == .working { return .opened }
        if event == .postToolUse || event == .postToolBatch { return .returned }
        return .closed
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
