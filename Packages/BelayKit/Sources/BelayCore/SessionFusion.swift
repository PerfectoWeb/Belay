import Foundation

/// How the two tiers of readings are fused into one activity, and when
/// that answer can change with no new input.
extension SessionState {
    /// The fusion rule from docs/03, evaluated against `now`.
    ///
    /// An exact observation outranks any inferred one while it is fresh, which
    /// is what stops a lagging file write from resurrecting a finished turn. Once
    /// hooks go quiet for `freshness`, the file watcher takes over again.
    public func effectiveActivity(
        now: Date, freshness: TimeInterval, toolCallBudget: TimeInterval = .infinity
    ) -> SessionActivity {
        if exact?.activity == .ended || inferred?.activity == .ended { return .ended }
        if let exact {
            let fresh = now.timeIntervalSince(exact.at) <= freshness
            let running = isInsideToolCall(now: now, budget: toolCallBudget)
            let backgrounded = isInsideBackground(now: now)
            if fresh || running || backgrounded { return exact.activity }
            // Stale, but still the last word unless the transcript has moved
            // since: a reading older than the hook cannot know more than it.
            // A parked session, its last record a tool call waiting on a
            // wake-up, used to turn "working" five minutes after its Stop and
            // be reported as gone quiet when the TTL took it.
            guard let inferred, inferred.at > exact.at + Self.inferredLead else {
                return exact.activity
            }
            return inferred.activity
        }
        if let inferred { return inferred.activity }
        return .idle
    }

    /// How much newer than the hook a transcript reading must be to outrank
    /// it once the hook is stale. The sweep stamps a write when it finds it,
    /// so the record a hook describes can carry a timestamp a little after
    /// the hook's own.
    public static let inferredLead: TimeInterval = returnGrace

    /// Whether the agent is still inside a tool call it opened and, if so,
    /// whether that claim is young enough to be worth believing.
    public func isInsideToolCall(now: Date, budget: TimeInterval) -> Bool {
        guard let since = openToolCallSince else { return false }
        return now.timeIntervalSince(since) <= budget
    }

    /// Whether a Stop's background-task claim is still young enough to hold.
    public func isInsideBackground(now: Date) -> Bool {
        guard let since = backgroundSince else { return false }
        return now.timeIntervalSince(since) <= AwakePolicy.backgroundTasksBudget
    }

    /// The moment an exact reading stops outranking the inferred one, which is
    /// the earliest time `effectiveActivity` can flip with no new input at all.
    /// `nil` when there is nothing to flip to, or the two already agree — the
    /// crossing changes nothing then. Lets the driver wake exactly at the flip
    /// instead of noticing it up to a safety tick late.
    public func exactFreshnessDeadline(window: TimeInterval, toolCallBudget: TimeInterval) -> Date? {
        guard let exact, let inferred, exact.activity != inferred.activity,
            inferred.at > exact.at + Self.inferredLead
        else { return nil }
        // An open bracket suspends the crossing, so the moment worth waking for
        // is the bracket's own ceiling instead.
        if let since = openToolCallSince {
            let ceiling = since + toolCallBudget
            return max(ceiling, exact.at + window)
        }
        if let since = backgroundSince {
            let ceiling = since + AwakePolicy.backgroundTasksBudget
            return max(ceiling, exact.at + window)
        }
        return exact.at + window
    }
}
