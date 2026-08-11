# VigilPower

Everything that touches IOKit, and nothing that decides anything.

`PowerAssertionController` owns at most one live assertion per kind, process-wide,
and takes `hold`/`release` from the coordinator without an opinion about why.
`IOKitPowerAssertionBackend` is the real `IOPMAssertionCreateWithProperties` call;
`MockPowerAssertionBackend` is what the tests drive. `PowerSourceMonitor` reports
AC, charge and Low Power Mode. `SystemSleepObserver` relays sleep and wake.
`TerminationSignalWatch` releases on `SIGTERM` and `SIGINT`.

**Depends on:** `VigilSupport`. It has never heard of a session and does not
import `VigilCore`.

## Things that might surprise you

**The timeout is the safety model, not a detail.** Every assertion is born with
`kIOPMAssertionTimeoutKey` (120 s) and `kIOPMAssertionTimeoutActionRelease`, and
a refresh task re-arms it at 75% of that lifetime with `IOPMAssertionSetProperty`
rather than release-and-recreate. If Vigil crashes, hangs or is killed, the Mac
returns to normal sleep within two minutes with no cleanup code involved. The
full argument is `docs/adr/001`.

**`release()` forgets the handle before it calls IOKit.** If the release throws,
retrying a stale assertion ID forever is worse than letting the assertion's own
timeout reap it. Reconciliation is also per-kind, so a failure on the display
assertion cannot take the system assertion down with it.

**`SystemSleepObserver` does not observe anything.** It is a relay: the app layer
calls `report(_:)`. `NSWorkspace.willSleepNotification` is posted only on
`NSWorkspace`'s own notification centre, and nothing but `VigilApp` may import
AppKit. The AppKit-free alternative, `IORegisterForSystemPower`, would oblige this
module to own a run loop and acknowledge every power change with
`IOAllowPowerChange` — get that wrong and you delay or veto system sleep, which is
precisely the bug this app must never have.

**`PowerSourceMonitor` polls, on purpose.** A `DispatchSourceTimer` with a 15 s
floor and 20% leeway beats `IOPSNotificationCreateRunLoopSource` here: the
notification source needs a live run loop and a C callback trampoline, and battery
state does not move fast enough to be worth either. It publishes on change only.

**`TerminationSignalWatch` sets `SIG_IGN` before installing its source.**
`DispatchSourceSignal` never fires while the default disposition is "terminate the
process", so the default has to go first. Pass `exitsProcess: false` only from
tests.
