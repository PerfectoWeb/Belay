# BelayCore

The decision layer, and the vocabulary every other module speaks.

`ActivitySignal` in, `AwakeDecision` out. `SignalBus` fans the providers together;
`ActivityCoordinator` holds the session ledger and the policy and decides whether
the Mac should stay awake; `CoordinatorSnapshot` is the immutable view the UI
renders. `AwakePolicy` declares every tunable, with the defaults that make Belay
behave correctly for someone who never opens Settings.

**Depends on:** `BelaySupport`, and nothing else — not IOKit, not the filesystem,
not AppKit, not `UserDefaults`, not the wall clock. That is what lets the suite
drive hours of behaviour in milliseconds.

## Things that might surprise you

**`Reading` is called `Reading` because `Observation` was taken.** It used to be
`public struct Observation`, which shadowed the *Observation module* inside the
`@Observable` macro expansion and broke every module that imported both. The name
is not a style choice; do not rename it back.

**`ActivityCoordinator` deliberately owns no timer.** `evaluate()` is a pure
function of (recorded signals, policy, power conditions, `clock.now`). Something
still has to call it as time passes, and that is `CoordinatorDriver`'s entire
job: it sleeps until the coordinator's own `nextDeadline`, capped at 60 s, rather
than polling.

**…which is why `CoordinatorDriver.nudge()` exists.** The driver computes its
deadline *before* the newest signal arrives and has no way to learn about it, so
without an explicit nudge a release can land up to a minute late — 45 s of idle
inference plus 90 s of grace plus 60 s of nap breaks the PRD's two-minute
promise. Call `nudge()` after every ingest, policy change and power change.

**Exact and inferred readings are kept in separate slots, not collapsed.**
`SessionState` holds both and `effectiveActivity(now:freshness:)` applies the
fusion rule against the current time on every evaluation. Collapsing on arrival
gives you the bug where a hook says "done", a trailing disk flush says "still
writing", and whichever landed last wins forever.

**The hold reason is sticky through the grace period.** `HoldReason` survives
cooling-down unchanged; only `BelayState` moves. Swapping the reason the moment a
turn ended re-emitted a decision on every pause between two tool calls, which is
exactly the churn the flapping test forbids.

**A session waiting on the user outlives the plain TTL.** `SessionLedger.ttl`
gives `awaitingUser` sessions `max(sessionTTL, awaitingUserBudget)`, because a
blocked session emits nothing by definition and the 10-minute TTL would evict it
before its 15-minute budget could ever be reached. It is a knowing deviation from
the literal wording of `docs/00-INVARIANTS.md` invariant 3, bounded by the budget so nothing
stale can pin the Mac awake. Recorded as D9 in `docs/PROJECT_STATE.md`.
