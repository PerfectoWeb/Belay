extension SessionActivity {
    /// The `state=` vocabulary the generic webhook integration documents.
    ///
    /// Lives in `VigilCore` because three places need it and must not drift: the
    /// receiver that parses the query, the provider that attributes the report,
    /// and the README that tells people what to send. An unrecognised state is
    /// rejected, never guessed — inventing `.working` from a typo would hold the
    /// Mac awake for a reason nobody can find.
    public init?(webhookState state: String) {
        switch state.lowercased() {
        case "working", "busy", "start": self = .working
        case "idle", "stop", "done": self = .idle
        case "waiting", "blocked": self = .awaitingUser
        case "ended", "exit": self = .ended
        default: return nil
        }
    }
}
