# 11 — Risks, ranked

### R1 — Claude Code changes its on-disk format (high likelihood, high impact)
The transcript location, filename scheme and JSONL record shape are not a public
API contract. They will change.

*Mitigation:* the watcher's primary signal is **file growth**, which survives any
record-shape change. Structural parsing is a refinement layered on top, and every
parse failure must degrade to "the file grew, so something is happening" rather
than to "no signal". Keep the hook bridge as the precise path. Add a settings
row showing detection health ("last signal 4 s ago — healthy") so a regression is
visible to users and reportable, not silent.

### R2 — Breaking the user's Claude Code (low likelihood, catastrophic impact)
A malformed `settings.json` merge or a slow/failing hook could damage or degrade
the thing the user cares about most.

*Mitigation:* backup before every write, atomic replace, refuse to write
non-plain-JSON files, diff preview before applying, one-click uninstall, and the
absolute rule that the shim always exits 0 within 50 ms. Add a test that runs a
real Claude Code turn with and without hooks installed and compares latency.

### R3 — Stuck assertion keeps the Mac awake forever (medium / high)
The one failure mode that would make users hate the app.

*Mitigation:* the assertion timeout model in `docs/04-POWER.md`. Session TTL.
Max-duration cap. Release on every termination path. A user-visible "Belay is
holding your Mac awake because X" string, always. If you only get one thing right
in this project, get this one right.

### R4 — App Review rejection (medium / medium)
Loopback socket and reading another tool's config directory both invite questions.

*Mitigation:* ship direct first, prepare review notes and a demo video, and keep
the socket behind a compile flag so a rejected MAS build can drop it in one line.
A reviewer-facing demo mode was built and then removed (PROJECT_STATE D16): it
could be triggered by a user and put fake sessions in a real panel. If review
needs one, it belongs in a separate scheme, not in the shipping menu.

### R5 — Sandbox breaks detection subtly (medium / high)
`KERN_PROCARGS2`, bookmark staleness, and FSEvents on a scoped resource all
behave differently sandboxed.

*Mitigation:* build and test the MAS scheme from M2 onward, not at M6. Every
detection path must have a sandbox test. Never depend on process arguments.

### R6 — False "idle" mid-task (low / high)
A long tool call with no output and no hooks looks identical to a finished turn
under Tier A.

*Closed in 1.6.2*, and in two halves, because the two builds have different
evidence available.

With hooks, a `PreToolUse` that has no `PostToolUse` after it is not a stale
reading but an unclosed bracket: the agent is demonstrably still inside the
call. While one is open the exact reading keeps its rank however old it is, and
the session is exempt from the ledger's TTL. Bounded by
`AwakePolicy.openToolCallBudget` (one hour) for the case where the agent is
killed between the two events, with the dead-process sweep and the awake limit
above that.

Without hooks — which is every App Store install — Tier C's busy-child probe
now walks the agent's whole process tree instead of its direct children. Claude
Code runs its Bash tool inside one long-lived shell, so the thing doing the work
is a grandchild and the old probe saw an old shell and nothing else. Same age
bound as before, breadth-first, depth-capped.

The old mitigation still underlies both: a generous `inferredIdleAfter` (45 s)
plus the coordinator grace period, which stacks to a ~2-minute tail on its own.

### R7 — macOS 27 Golden Gate changes menu bar / power behaviour (medium / low)
Releasing September 2026, Apple-silicon only, with further Liquid Glass changes.

*Mitigation:* template images and system-provided materials only — no hardcoded
colours or menu bar hacks. Test on the public beta during M7 and note results.

### R8 — Nobody knows they need this (high / high — the real product risk)
The engineering can be perfect and the app still invisible.

*Mitigation:* the "Claude needs your input" notification (PRD R7) is the hook
that makes people install it for a reason other than sleep. The README should
lead with the 15-second demo GIF of `pmset -g assertions` appearing and
disappearing on its own. Ship free, make the tip jar frictionless and silent.
