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
            // Stale, but still the last word unless the transcript moved after
            // the hooks fell silent. While they were fresh every prompt came
            // with its own hook, so a transcript reading from inside that
            // window only continues a turn: a parked session's tool call
            // waiting on a wake-up, or the records a /compact writes two
            // minutes after the Stop, used to turn "working" when the window
            // closed and be reported as gone quiet when the grace ran out.
            if let inferred, inferred.at > exact.at + freshness { return inferred.activity }
            // A Stop that claimed background tasks reads as working only for
            // the claim's budget; once that is spent, the Stop means what a
            // Stop means. Found live: the transcript's end_turn landed a
            // second before the hook, so the hook kept the last word and the
            // session expired as one that went quiet.
            if backgroundSince != nil { return .idle }
            return exact.activity
        }
        if let inferred { return inferred.activity }
        return .idle
    }

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
    ///
    /// A transcript reading outranks a hook only once it is newer than the
    /// hook's whole window, by which time the window has closed, so the flip
    /// is immediate. Only an open bracket can still hold the hook's word past
    /// that point, and then the moment worth waking for is the bracket's own
    /// ceiling.
    public func exactFreshnessDeadline(window: TimeInterval, toolCallBudget: TimeInterval) -> Date? {
        guard let exact, let inferred, exact.activity != inferred.activity,
            inferred.at > exact.at + window
        else { return nil }
        if let since = openToolCallSince {
            let ceiling = since + toolCallBudget
            return ceiling > inferred.at ? ceiling : nil
        }
        if let since = backgroundSince {
            let ceiling = since + AwakePolicy.backgroundTasksBudget
            return ceiling > inferred.at ? ceiling : nil
        }
        return nil
    }
}
