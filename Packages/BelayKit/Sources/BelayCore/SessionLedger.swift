import Foundation

/// The coordinator's session bookkeeping, as a value type.
///
/// Split out so the actor is only about policy and emission. Being a plain
/// struct also means the eviction rules can be tested without an actor, a clock
/// or a single `await`.
struct SessionLedger {
    private(set) var sessions: [SessionID: SessionState] = [:]
    /// Sessions that left the ledger, by ending or by expiry, and when: a
    /// heartbeat arriving afterwards is the provider still following the
    /// file, not the session coming back.
    /// Found live: a session closed with a prompt unanswered was reborn a
    /// minute later from the silence heartbeat, as a working session nothing
    /// would ever finish, and expired as one that went quiet.
    private(set) var ended: [SessionID: Date] = [:]
    /// What each session was doing at the last prune. A session that stops
    /// working and expires in the same breath is kept for one more look, so
    /// the snapshot shows it idle before it goes: a bracket's budget ends and
    /// the TTL has long passed, and the nudge used to see a working session
    /// vanish and call it gone quiet.
    private var lastActivities: [SessionID: SessionActivity] = [:]
    /// How long an ending is remembered. Longer than any grace a provider
    /// keeps heartbeating for after the last real word.
    static let endedMemory: TimeInterval = 60 * 60

    var ordered: [SessionState] {
        sessions.values.sorted { $0.firstSeen < $1.firstSeen }
    }

    var isEmpty: Bool { sessions.isEmpty }

    mutating func record(_ signal: ActivitySignal, now: Date) {
        if sessions[signal.session] == nil, let at = ended[signal.session] {
            if signal.heartbeat, now.timeIntervalSince(at) < Self.endedMemory { return }
            ended[signal.session] = nil
        }
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
        ended = ended.filter { now.timeIntervalSince($0.value) < Self.endedMemory }
        var activities: [SessionID: SessionActivity] = [:]
        var dropped: [SessionID] = []
        for (id, session) in sessions {
            let activity = session.effectiveActivity(
                now: now, freshness: policy.hookFreshnessWindow,
                toolCallBudget: AwakePolicy.openToolCallBudget)
            activities[id] = activity
            if !keeps(session, activity: activity, now: now, policy: policy) { dropped.append(id) }
        }
        // Every way out is remembered the same way: a heartbeat for a session
        // the TTL took is the provider still following the file, exactly as
        // after an end, and used to seed it again as a working session.
        for id in dropped {
            ended[id] = now
            sessions[id] = nil
        }
        lastActivities = activities.filter { sessions[$0.key] != nil }
    }

    private func keeps(
        _ session: SessionState, activity: SessionActivity, now: Date, policy: AwakePolicy
    ) -> Bool {
        if activity == .ended { return false }
        // Shown once more before it goes, so the snapshot carries the change.
        if activity != .working, lastActivities[session.id] == .working { return true }
        // A tool call emits nothing while it runs, so the plain TTL would
        // evict the very session the bracket exists to protect, ten
        // minutes into a half-hour test suite, with the hold going with it.
        if session.isInsideToolCall(now: now, budget: AwakePolicy.openToolCallBudget) {
            return true
        }
        // Same exemption for the background bracket: an idle-with-tasks
        // session emits nothing, and the plain TTL would evict it well
        // before its thirty minutes were up.
        if session.isInsideBackground(now: now) { return true }
        return !session.isExpired(now: now, ttl: Self.ttl(for: activity, policy: policy))
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
    /// holds. Recorded as D9 in docs/PROJECT_STATE.md (git history).
    static func ttl(for activity: SessionActivity, policy: AwakePolicy) -> TimeInterval {
        guard activity == .awaitingUser else { return policy.sessionTTL }
        return max(policy.sessionTTL, policy.awaitingUserBudget)
    }
}
