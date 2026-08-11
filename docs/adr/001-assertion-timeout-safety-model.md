# 001 — Assertion timeouts are the safety model

**Status:** accepted, implemented in M1

## Context

The failure mode that would make users hate Vigil is not "it let my Mac sleep
during a task" — it is "it kept my Mac awake for nine hours and I didn't notice"
(risk R3). A menu bar utility that pins the machine awake after it crashes, gets
force-quit, deadlocks, or is killed by the OS is worse than no utility at all,
because the user has no reason to suspect it and no obvious way to find out.

The naive design holds one IOKit assertion for as long as the app thinks work is
happening, and releases it on the way out. Every path in that sentence is a
liability: "for as long as the app thinks" depends on a state machine being
correct, and "on the way out" depends on a clean exit that `SIGKILL`, a kernel
panic, or a hung actor will not give us.

## Decision

Every assertion is created with a short `kIOPMAssertionTimeoutKey` (default
120 s) and `kIOPMAssertionTimeoutActionRelease`, and a refresh task re-arms it at
75% of that lifetime while the coordinator still says hold.

The deadline is owned by the *decision* layer, not the IOKit layer:
`AwakeDecision.hold(reason:until:)` carries it explicitly, so it is a value the
test suite can assert on rather than a side effect buried in a C API call.

Re-arming uses `IOPMAssertionSetProperty` on the timeout and details keys rather
than release-and-recreate. A real IOKit smoke test confirmed `SetProperty`
returns `kIOReturnSuccess` and that the updated details string appears in
`pmset -g assertions`; it is cheaper and, unlike recreate, cannot leave a window
where nothing is held.

## Consequences

Good, and the whole point:

- The app crashing, hanging, being force-quit or killed returns the Mac to normal
  sleep behaviour **within two minutes**, with no cleanup code involved. There is
  no such thing as a zombie caffeination.
- A deadlocked actor cannot silently keep the machine awake. The worst case is
  bounded by the timeout, not by the bug.
- `release()` failing is survivable: the controller drops the handle and lets the
  assertion's own timeout reap it, rather than retrying a stale ID forever.
- The user can audit all of it with one command, and see our human-readable
  reason and remaining timeout:

  ```
  pmset -g assertions | grep -i vigil
  ```

Costs, accepted:

- A wakeup every 90 s while holding. Measured at 0.0% CPU over a 200 s sample, so
  it does not threaten the `docs/08` budget. Nothing wakes while released.
- Two moving parts (timeout + refresh) instead of one. Covered by a property test
  running 5,000 seeded operation sequences against a mock backend, asserting at
  most one live assertion per type and balanced create/release throughout.

Verified on the host at M1, not merely unit-tested: the timeout appears in
`pmset` output, counts down 100→85→70→55→40, and jumps back to 117 when the
refresh fires — a ~30 s margin before expiry.

## Alternatives considered

**`caffeinate` as a subprocess.** A child process to babysit, no structured
reason string, no timeout semantics of its own, and a red flag in App Review.
Explicitly forbidden by `docs/00-INVARIANTS.md`.

**`ProcessInfo.beginActivity`.** Coarse, no timeout, invisible in
`pmset -g assertions`, and no human-readable reason. The user could not verify
what Vigil was doing, which removes the argument that converts skeptics.

**A long assertion released on exit.** Depends on a clean exit path existing.
`SIGKILL` and kernel panics do not offer one. This is precisely the design that
produces the nine-hour bug.

**`kIOPMAssertionTypePreventSystemSleep`.** Wrong type: it is for kernel and
driver scenarios, prevents sleep far more aggressively than a user app should,
and is not what "keep working overnight" needs.
