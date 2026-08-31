# 04 – Power management

## The mechanism

Use IOKit power assertions via `IOPMAssertionCreateWithProperties`. Not
`caffeinate` (a subprocess we'd have to babysit, and a red flag in App Review),
not `ProcessInfo.beginActivity` (coarse, no timeout, no visibility in
`pmset -g assertions`, no human-readable reason for the user).

```swift
let properties: [String: Any] = [
    kIOPMAssertionTypeKey as String: kIOPMAssertionTypePreventUserIdleSystemSleep,
    kIOPMAssertionNameKey as String: "Belay",
    kIOPMAssertionDetailsKey as String: reason,          // "Claude Code is working in acme-api"
    kIOPMAssertionHumanReadableReasonKey as String: localizedReason,
    kIOPMAssertionLocalizationBundlePathKey as String: Bundle.main.bundlePath,
    kIOPMAssertionTimeoutKey as String: timeout,          // seconds, NSNumber
    kIOPMAssertionTimeoutActionKey as String: kIOPMAssertionTimeoutActionRelease,
]
```

### Assertion types

| Type | Use |
|---|---|
| `kIOPMAssertionTypePreventUserIdleSystemSleep` | **Primary.** System stays up; display may sleep. This is what the user actually wants overnight. |
| `kIOPMAssertionTypePreventUserIdleDisplaySleep` | Optional, off by default, exposed as "Also keep the display awake". |
| `kIOPMAssertNetworkClientActive` | Rides along with every hold since 1.3.2. Awake but with parked network clients is still a dead run: SSH drops, streaming replies stall. A request, not a promise. |

Do not use `kIOPMAssertionTypeNoIdleSleep`/`NoDisplaySleep` (legacy aliases) or
`PreventSystemSleep` (that one is for kernel-level/driver scenarios and is not
appropriate for a user app).

## The timeout is the safety design, not a detail

Every assertion is created with a **short timeout** (default 120 s) and
`kIOPMAssertionTimeoutActionRelease`. While the coordinator says "hold", a
refresh task re-arms it before expiry (`IOPMAssertionSetProperty` on the timeout
key, or release-and-recreate – measure both, prefer whichever is cleaner; a
recreate every 90 s is negligible).

Consequences, all good:

- App crashes, hangs, is force-quit, or is killed by the OS → the Mac returns to
  normal sleep behaviour within two minutes. No zombie caffeination, ever.
- The user can see exactly what's happening and why in `pmset -g assertions`,
  including our human-readable reason string.
- A deadlocked actor cannot silently keep the machine awake for 9 hours.

## PowerAssertionController

An actor owning at most one assertion ID per type, with a strictly idempotent
API:

```swift
public actor PowerAssertionController {
    public func hold(reason: String, includeDisplay: Bool) async
    public func release() async
    public var isHeld: Bool { get }
}
```

Requirements:

- `hold` twice in a row must not create a second assertion; it updates the
  reason string and re-arms the timeout.
- `release` when nothing is held is a no-op that does not log an error.
- Wrap the raw IOKit calls behind a `PowerAssertionBackend` protocol with a
  `MockPowerAssertionBackend` for tests. Assert in tests that create/release
  calls are balanced across thousands of randomised state transitions.
- Check the `IOReturn` from every call. On failure, log once, surface a
  non-blocking warning in the UI, and re-attempt on the next refresh tick –
  do not spam.

## Release triggers (all of them must be wired)

| Trigger | Notes |
|---|---|
| Coordinator emits `.release` | The normal path |
| `NSApplication.willTerminateNotification` | Synchronous release before exit |
| `SIGTERM` / `SIGINT` | `DispatchSourceSignal`; release then exit |
| `NSWorkspace.willSleepNotification` | Release; re-evaluate on `didWakeNotification` |
| Battery guard trip | See below |
| Max-duration cap reached | Emit a notification explaining why |
| User switches mode to Off | Immediate |

On `didWakeNotification`, do a **full resync**: re-seed transcript cursors,
re-enumerate processes, and re-derive state from scratch. Signals that arrived
"during" sleep are meaningless and timestamps will look bizarre.

## Battery and thermal policy

- `IOPSCopyPowerSourcesInfo` for charge level and AC status.
- Default: on battery below 20%, release and refuse to re-arm; show the reason
  in the panel. Configurable, including "ignore" for users who know what they're doing.
- Respect `ProcessInfo.processInfo.isLowPowerModeEnabled` as a soft signal:
  default behaviour is to keep working (the user explicitly wants the agent to
  finish) but shorten the grace period. Make it a setting; don't be clever
  silently.
- Do not attempt anything with thermal state in v1.0. (1.3's lid hold is the
  deliberate exception: its thermal release is one of the two mandatory
  guards, and it applies only with the lid shut. Since 1.3.1, both lid guards
  say which one fired: the time cap and the heat release each post a
  notification when they end a hold.)

## Things to document honestly in the FAQ

- **Lid closed:** an idle-sleep assertion does not keep a MacBook awake with the
  lid shut. macOS enters clamshell sleep unless the machine is on AC power with
  an external display/keyboard attached. No assertion changes this – which is
  why 1.3's opt-in lid hold is not one: a privileged helper (direct builds
  only) holds the kernel's `SleepDisabled` flag on a heartbeat leash, with a
  hard cap and a thermal release. Measured 2026-08-18 on battery, no display:
  flag up, the lid shut and music kept playing; flag down, same lid, asleep in
  seventy seconds ("Clamshell Sleep" in `pmset -g log`).
- **Display sleep is normal.** By default the screen still turns off. That's
  intentional and saves real power; the machine underneath stays awake.
- **Verify it yourself:** `pmset -g assertions | grep -i belay`. Put this line in
  the README – it converts skeptics.
