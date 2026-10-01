import BelayCore

extension AutoAllower {
    /// Whether a session of `provider` can be waiting on a card. A card is
    /// raised inside a tool call, so while the hooks report on the agent a
    /// visit needs a `PreToolUse` that has not returned. Found live: a session
    /// that had just stopped was visited for nothing, seconds before it began
    /// its next turn by itself. Without hooks there is no telling, and the
    /// visit goes ahead.
    nonisolated static func mayBeAsking(_ sessions: [SessionState], provider: ProviderID) -> Bool {
        let own = sessions.filter { $0.provider == provider }
        guard own.contains(where: { $0.exact != nil }) else { return true }
        return own.contains { $0.openToolCallSince != nil }
    }
}

extension AppDelegate {
    /// What Auto Allow needs from the rest of the app: which agents are on,
    /// and whether one of them can be asking at all.
    func wireAutoAllow() {
        let allower = appState.modules.autoAllow
        allower.agentIsOn = { [weak settings] app in
            settings?.isEnabled(app == .codex ? .codex : .claudeCode) ?? true
        }
        // Whether Codex's hooks bracket its cards is unmeasured, so only
        // Claude's visits wait for an open tool call.
        allower.mayHaveRequest = { [weak appState] app in
            guard app == .claude, let sessions = appState?.snapshot.sessions else { return true }
            return AutoAllower.mayBeAsking(sessions, provider: .claudeCode)
        }
    }
}
