import Foundation

public struct SessionID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// Session identifiers are user-identifying enough to keep out of logs.
    public var description: String { "session(\(rawValue.prefix(8)))" }
}

public enum ProviderID: String, Sendable, CaseIterable, Codable {
    case claudeCode
    case codex
    case cline
    case copilot
    case generic
}

public enum SessionActivity: Sendable, Equatable {
    /// The model or a tool is running.
    case working
    /// Blocked on a permission prompt or a question to the user.
    case awaitingUser
    /// The turn finished; nothing is running.
    case idle
    /// The session is gone: process exited, or an explicit end event arrived.
    case ended
}

/// How much a signal can be trusted. A hook reports what actually happened; a
/// file watcher infers it. When both describe the same session, exact wins —
/// see `SessionState.record` and docs/03 "Fusion rules".
public enum Confidence: Int, Sendable, Comparable {
    case inferred
    case exact

    public static func < (lhs: Confidence, rhs: Confidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Whether a signal marks the start or the end of a tool call.
///
/// Only an agent's own hooks can say this, so only Tier B ever sets it: a file
/// watcher sees a tool call and a finished turn as the same silence, which is
/// the whole problem this exists to solve. `nil` means "no opinion", which is
/// what every inferred signal carries.
/// What kind of work a tool call is, coarse on purpose: the panel shows this
/// beside "Working", and "Running a command" is an answer where a raw tool
/// name would be jargon. Never the tool's arguments — a category cannot leak
/// a prompt or a path.
public enum ToolCategory: String, Sendable, Equatable, Codable {
    case command
    case edit
    case read
    case search
    case web
    case subagent
    case tool
}

public enum ToolCallEdge: Sendable, Equatable {
    /// The agent has entered a tool call and is blocked inside it.
    case opened
    /// The tool itself returned (`PostToolUse`). Kept apart from `closed`
    /// because hooks are fired asynchronously and can land out of order: the
    /// return of tool N arriving just after the start of tool N+1 must not
    /// wipe the newer bracket, and only a return is ever racing an open that
    /// closely.
    case returned
    /// Whatever was running is over: the turn stopped, or a new prompt
    /// arrived. Anything that is not the start of a tool call ends one,
    /// because the agent cannot be inside two at once.
    case closed
}

public struct ActivitySignal: Sendable, Equatable {
    public let provider: ProviderID
    public let session: SessionID
    public let activity: SessionActivity
    /// Display name for the UI, typically the project folder name.
    public let workspace: String?
    /// The session that spawned this one, when it is a subagent. A subagent is a
    /// session in its own right — it works, goes quiet and dies independently —
    /// so it is tracked separately and only *presented* under its parent.
    public let parent: SessionID?
    /// The agent's configured type, e.g. `general-purpose`. Structural only:
    /// what the user asked the agent to do is never read (docs/06).
    public let kind: String?
    /// The agent's own name for this session, unique per session where the
    /// provider knows one. Two sessions in one checkout are otherwise
    /// indistinguishable in the UI; this is what tells them apart.
    public let name: String?
    public let timestamp: Date
    public let confidence: Confidence
    /// Set by the hook bridge only. See `SessionState.openToolCallSince`.
    public let toolCall: ToolCallEdge?
    /// The session's cumulative token count as its own transcript reports it
    /// (input + output; never cache reads). Providers normalize to a running
    /// total so the consumer only ever moves the number forward. Numbers,
    /// never text: the R9 boundary holds.
    public let tokensTotal: Int?
    /// The category of the tool call an `.opened` edge is entering. Only ever
    /// set beside `.opened`; every close clears it downstream.
    public let tool: ToolCategory?

    public init(
        provider: ProviderID,
        session: SessionID,
        activity: SessionActivity,
        workspace: String?,
        parent: SessionID? = nil,
        kind: String? = nil,
        name: String? = nil,
        timestamp: Date,
        confidence: Confidence,
        toolCall: ToolCallEdge? = nil,
        tokensTotal: Int? = nil,
        tool: ToolCategory? = nil
    ) {
        self.provider = provider
        self.session = session
        self.activity = activity
        self.workspace = workspace
        self.parent = parent
        self.kind = kind
        self.name = name
        self.timestamp = timestamp
        self.confidence = confidence
        self.toolCall = toolCall
        self.tokensTotal = tokensTotal
        self.tool = tool
    }
}

/// What the coordinator wants the power layer to do.
///
/// `hold` carries its own deadline so the decision layer, not IOKit, owns the
/// safety timeout and tests can assert on it directly (docs/02).
public enum AwakeDecision: Sendable, Equatable {
    case release
    case hold(reason: String, until: Date)

    public var isHold: Bool {
        if case .hold = self { return true }
        return false
    }
}
