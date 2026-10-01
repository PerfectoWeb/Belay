import Foundation

/// What one provider claimed about one session, and when. Named `Reading`
/// rather than `Observation` so it cannot shadow the Observation framework the
/// app layer needs for `@Observable`.
public struct Reading: Sendable, Equatable {
    public var activity: SessionActivity
    public var at: Date

    public init(activity: SessionActivity, at: Date) {
        self.activity = activity
        self.at = at
    }
}

/// Everything the coordinator knows about a single agent session.
///
/// Exact and inferred observations are kept in separate slots rather than
/// collapsed on arrival. Collapsing early is the bug docs/03 warns about: a hook
/// says "done", a trailing disk flush says "still writing", and whichever landed
/// last wins forever. Keeping both lets `effectiveActivity` apply the fusion
/// rule against the current time, every time.
public struct SessionState: Sendable, Equatable, Identifiable {
    public let id: SessionID
    public let provider: ProviderID
    public var workspace: String?
    /// Set when this session is a subagent of another. Only the UI cares: the
    /// policy layer treats parents and children alike, because a working
    /// subagent is exactly as much a reason to stay awake as a working session.
    public var parent: SessionID?
    /// The agent's configured type, for display. Never its instructions.
    public var kind: String?
    /// The agent's own name for this session, for display. The UI shows it only
    /// when it has to — see `SessionRow.disambiguate`.
    public var name: String?
    public var exact: Reading?
    public var inferred: Reading?
    /// When the agent entered a tool call it has not come back from.
    ///
    /// This is the answer to R6, and the reason Precise Detection is worth
    /// turning on. A tool call that runs for half an hour — a test suite, a
    /// build — writes nothing at all, so every inferred reading says the turn
    /// is over, and the exact reading that said otherwise goes stale after
    /// `hookFreshnessWindow`. But a `PreToolUse` with no `PostToolUse` after it
    /// is not a stale reading: it is an unclosed bracket, and the agent is
    /// demonstrably still inside it. While the bracket is open the exact
    /// reading keeps its rank however old it is.
    ///
    /// Bounded, because a bracket can be lost: an agent killed mid-tool fires
    /// nothing. `AwakePolicy.openToolCallBudget` is the ceiling, the process
    /// sweep ends genuinely dead sessions sooner, and the awake limit sits
    /// above both.
    public var openToolCallSince: Date?
    /// When a `Stop` last claimed background tasks were still running. The
    /// mirror of `openToolCallSince` for work that outlives the turn: bounded
    /// by `AwakePolicy.backgroundTasksBudget` because no later hook can ever
    /// confirm the claim — trust with a timer, never an open-ended hold.
    public var backgroundSince: Date?
    /// What kind of tool the open bracket is inside, for the panel's badge.
    /// Lives and dies with the bracket: every close clears it, and the
    /// reordered-return grace that spares the bracket spares this too.
    public var activeTool: ToolCategory?
    /// Cumulative tokens the session's own transcript reports. Forward-only:
    /// signals may arrive out of order, and a total can never shrink.
    public var tokens: Int = 0

    /// When this session first became known. Drives the UI's elapsed column.
    public let firstSeen: Date
    /// When the session most recently entered `.working`, for elapsed display.
    public var workingSince: Date?
    /// When the session most recently entered `.awaitingUser`, for the budget.
    public var awaitingSince: Date?

    public init(
        id: SessionID,
        provider: ProviderID,
        workspace: String?,
        parent: SessionID? = nil,
        kind: String? = nil,
        name: String? = nil,
        firstSeen: Date
    ) {
        self.id = id
        self.provider = provider
        self.workspace = workspace
        self.parent = parent
        self.kind = kind
        self.name = name
        self.firstSeen = firstSeen
    }

    public var lastSignal: Date {
        let readings = [exact?.at, inferred?.at, lastHeartbeat].compactMap { $0 }
        return readings.max() ?? firstSeen
    }

    /// The last time bytes landed in the transcript without a readable
    /// record. Kept apart from `inferred` so a flush after a Stop refreshes
    /// the TTL without lending the stale reading a newer date.
    public var lastHeartbeat: Date?

    /// Records an observation, ignoring anything older than what that slot
    /// already holds. Out-of-order delivery is normal: the transcript watcher
    /// batches, and hooks are fired asynchronously.
    public mutating func record(_ signal: ActivitySignal) {
        if let total = signal.tokensTotal, total > tokens { tokens = total }
        let reading = Reading(activity: signal.activity, at: signal.timestamp)
        switch signal.confidence {
        case .exact:
            if let existing = exact, existing.at > signal.timestamp { return }
            exact = reading
            recordToolCallEdge(signal)
            // Behind the guard on purpose: a Stop only ever arrives exact, and
            // a retried or reordered one must not clear a bracket a newer
            // Stop armed, nor resurrect one a newer Stop released.
            if let running = signal.backgroundTasks {
                backgroundSince = running > 0 ? signal.timestamp : nil
            }
        case .inferred:
            guard recordInferred(reading, heartbeat: signal.heartbeat) else { return }
        }
        if let workspace = signal.workspace, !workspace.isEmpty {
            self.workspace = workspace
        }
        // Parentage is structural and cannot change; a later signal that has
        // simply lost track of it must not orphan the session in the list.
        if parent == nil { parent = signal.parent }
        if kind == nil { kind = signal.kind }
        // Tier C learns the name a sweep or two after the transcript watcher has
        // already reported the session, so this arrives late and must not be
        // dropped — but it never changes once known.
        if name == nil { name = signal.name }
    }

    /// Whether the reading was taken. A heartbeat is life, not news: the
    /// transcript was flushed or continued, not opened or closed, so only
    /// `lastHeartbeat` moves. The one exception is a session with no reading
    /// yet, adopted mid-turn: its first heartbeat is all there is to go on.
    private mutating func recordInferred(_ reading: Reading, heartbeat: Bool) -> Bool {
        if let existing = inferred, existing.at > reading.at { return false }
        if heartbeat, inferred != nil {
            lastHeartbeat = max(lastHeartbeat ?? .distantPast, reading.at)
            return false
        }
        inferred = reading
        return true
    }

    /// How close behind an open a tool's *return* may land and still be the
    /// previous call's, not this one's. Hooks are fire-and-forget curls and
    /// the bridge stamps receipt time, so between back-to-back tool calls the
    /// return of the first can arrive milliseconds after the start of the
    /// second — with the newer timestamp. Two seconds is generous for two
    /// loopback posts fired together; the cost of guessing wrong is a bracket
    /// that stays open until the turn's own Stop, which closes unconditionally.
    public static let returnGrace: TimeInterval = 2

    /// Ordered with the reading, not before it: a hook that arrived out of
    /// order must not close a bracket a newer one opened. Receipt timestamps
    /// arrive in order by construction, so the timestamp guard in `record`
    /// can never catch that race — the grace below is what does.
    private mutating func recordToolCallEdge(_ signal: ActivitySignal) {
        switch signal.toolCall {
        case .opened:
            openToolCallSince = signal.timestamp
            activeTool = signal.tool
        case .returned:
            // A return landing this close behind an open is the *previous*
            // call's, reordered in flight. Leave the bracket alone; if the
            // guess is wrong, Stop or the next event closes it anyway.
            let opened = openToolCallSince ?? .distantPast
            if signal.timestamp.timeIntervalSince(opened) < Self.returnGrace { return }
            openToolCallSince = nil
            activeTool = nil
        case .closed:
            openToolCallSince = nil
            activeTool = nil
        case nil:
            break
        }
    }

    public func isExpired(now: Date, ttl: TimeInterval) -> Bool {
        now.timeIntervalSince(lastSignal) > ttl
    }
}
