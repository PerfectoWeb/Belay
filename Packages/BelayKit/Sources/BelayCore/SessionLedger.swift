import Foundation

/// The coordinator's session bookkeeping, as a value type.
///
/// Split out so the actor is only about policy and emission. Being a plain
/// struct also means the eviction rules can be tested without an actor, a clock
/// or a single `await`.
struct SessionLedger {
    private(set) var sessions: [SessionID: SessionState] = [:]

    var ordered: [SessionState] {
        sessions.values.sorted { $0.firstSeen < $1.firstSeen }
    }

    var isEmpty: Bool { sessions.isEmpty }

    mutating func record(_ signal: ActivitySignal, now: Date) {
        sessions[
            signal.session,
            default: SessionState(
                id: signal.session,
                provider: signal.provider,
                workspace: signal.workspace,
                parent: signal.parent,
                kind: signal.kind,
                name: signal.name,
                firstSeen: min(signal.timestamp, now)
            )
        ].record(signal)
    }

    mutating func removeAll() {
        sessions.removeAll()
    }

    mutating func prune(now: Date, policy: AwakePolicy) {
        sessions = sessions.filter { _, session in
            let activity = session.effectiveActivity(
                now: now, freshness: policy.hookFreshnessWindow,
                toolCallBudget: AwakePolicy.openToolCallBudget)
            guard activity != .ended else { return false }
            // A tool call emits nothing while it runs, so the plain TTL would
            // evict the very session the bracket exists to protect — ten
            // minutes into a half-hour test suite, with the hold going with it.
            if session.isInsideToolCall(now: now, budget: AwakePolicy.openToolCallBudget) {
                return true
            }
            return !session.isExpired(now: now, ttl: Self.ttl(for: activity, policy: policy))
        }
    }

    /// Recomputes fused activity and the per-session transition timestamps that
    /// the awaiting-user budget and the UI's elapsed column are measured from.
    mutating func refreshDerived(now: Date, policy: AwakePolicy) -> [SessionID: SessionActivity] {
        var activities: [SessionID: SessionActivity] = [:]
        for (id, var session) in sessions {
            let activity = session.effectiveActivity(
                now: now, freshness: policy.hookFreshnessWindow,
                toolCallBudget: AwakePolicy.openToolCallBudget)
            activities[id] = activity
            session.workingSince = activity == .working ? (session.workingSince ?? now) : nil
            session.awaitingSince = activity == .awaitingUser ? (session.awaitingSince ?? now) : nil
            sessions[id] = session
        }
        return activities
    }

    /// Times at which a session's own state could change with no new input.
    func deadlines(policy: AwakePolicy) -> [Date] {
        sessions.values.flatMap { session -> [Date] in
            var dates = [session.lastSignal + policy.sessionTTL]
            if let awaitingSince = session.awaitingSince {
                dates.append(awaitingSince + policy.awaitingUserBudget)
            }
            // The exact-reading freshness crossing: when a hook goes quiet the
            // fused activity flips with no new signal, and without this the
            // driver only noticed it at its 60 s safety tick.
            let crossing = session.exactFreshnessDeadline(
                window: policy.hookFreshnessWindow,
                toolCallBudget: AwakePolicy.openToolCallBudget)
            if let crossing { dates.append(crossing) }
            return dates
        }
    }

    /// A session waiting on the user emits nothing by definition, so the plain
    /// TTL would evict it before its awaiting budget ran out and PRD R7's
    /// 15-minute promise could never actually be kept. The exemption is bounded
    /// by the budget, so no session outlives `max(sessionTTL, awaitingUserBudget)`
    /// and invariant 3's purpose — nothing stale pins the Mac awake — still
    /// holds. Recorded as D9 in docs/PROJECT_STATE.md.
    static func ttl(for activity: SessionActivity, policy: AwakePolicy) -> TimeInterval {
        guard activity == .awaitingUser else { return policy.sessionTTL }
        return max(policy.sessionTTL, policy.awaitingUserBudget)
    }
}
