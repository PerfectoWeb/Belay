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
    public func effectiveActivity(now: Date, freshness: TimeInterval) -> SessionActivity {
        if exact?.activity == .ended || inferred?.activity == .ended { return .ended }
        if let exact, now.timeIntervalSince(exact.at) <= freshness { return exact.activity }
        if let inferred { return inferred.activity }
        return exact?.activity ?? .idle
    }

    public func isExpired(now: Date, ttl: TimeInterval) -> Bool {
        now.timeIntervalSince(lastSignal) > ttl
    }

    /// The moment an exact reading stops outranking the inferred one, which is
    /// the earliest time `effectiveActivity` can flip with no new input at all.
    /// `nil` when there is nothing to flip to, or the two already agree — the
    /// crossing changes nothing then. Lets the driver wake exactly at the flip
    /// instead of noticing it up to a safety tick late.
    public func exactFreshnessDeadline(window: TimeInterval) -> Date? {
        guard let exact, let inferred, exact.activity != inferred.activity else { return nil }
        return exact.at + window
    }
}
