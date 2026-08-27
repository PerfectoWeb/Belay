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
        switch (exact?.at, inferred?.at) {
        case (let exactAt?, let inferredAt?): return max(exactAt, inferredAt)
        case (let exactAt?, nil): return exactAt
        case (nil, let inferredAt?): return inferredAt
        case (nil, nil): return firstSeen
        }
    }

    /// Records an observation, ignoring anything older than what that slot
    /// already holds. Out-of-order delivery is normal: the transcript watcher
    /// batches, and hooks are fired asynchronously.
    public mutating func record(_ signal: ActivitySignal) {
        let reading = Reading(activity: signal.activity, at: signal.timestamp)
        switch signal.confidence {
        case .exact:
            if let existing = exact, existing.at > signal.timestamp { return }
            exact = reading
            // Ordered with the reading, not before it: a hook that arrived out
            // of order must not close a bracket a newer one opened.
            switch signal.toolCall {
            case .opened: openToolCallSince = signal.timestamp
            case .closed: openToolCallSince = nil
            case nil: break
            }
        case .inferred:
            if let existing = inferred, existing.at > signal.timestamp { return }
            inferred = reading
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

    /// The fusion rule from docs/03, evaluated against `now`.
    ///
    /// An exact observation outranks any inferred one while it is fresh, which
    /// is what stops a lagging file write from resurrecting a finished turn. Once
    /// hooks go quiet for `freshness`, the file watcher takes over again.
    public func effectiveActivity(
        now: Date, freshness: TimeInterval, toolCallBudget: TimeInterval = .infinity
    ) -> SessionActivity {
        if exact?.activity == .ended || inferred?.activity == .ended { return .ended }
        if let exact,
            now.timeIntervalSince(exact.at) <= freshness
                || isInsideToolCall(now: now, budget: toolCallBudget)
        {
            return exact.activity
        }
        if let inferred { return inferred.activity }
        return exact?.activity ?? .idle
    }

    /// Whether the agent is still inside a tool call it opened and, if so,
    /// whether that claim is young enough to be worth believing.
    public func isInsideToolCall(now: Date, budget: TimeInterval) -> Bool {
        guard let since = openToolCallSince else { return false }
        return now.timeIntervalSince(since) <= budget
    }

    public func isExpired(now: Date, ttl: TimeInterval) -> Bool {
        now.timeIntervalSince(lastSignal) > ttl
    }

    /// The moment an exact reading stops outranking the inferred one, which is
    /// the earliest time `effectiveActivity` can flip with no new input at all.
    /// `nil` when there is nothing to flip to, or the two already agree — the
    /// crossing changes nothing then. Lets the driver wake exactly at the flip
    /// instead of noticing it up to a safety tick late.
    public func exactFreshnessDeadline(window: TimeInterval, toolCallBudget: TimeInterval) -> Date? {
        guard let exact, let inferred, exact.activity != inferred.activity else { return nil }
        // An open bracket suspends the crossing, so the moment worth waking for
        // is the bracket's own ceiling instead.
        if let since = openToolCallSince {
            let ceiling = since + toolCallBudget
            return max(ceiling, exact.at + window)
        }
        return exact.at + window
    }
}
