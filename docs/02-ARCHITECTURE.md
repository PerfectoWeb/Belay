# 02 — Architecture

## Shape

Local Swift packages under `Packages/`, consumed by a thin app target. This is
what makes the project testable, parallelisable across agents, and pleasant to
extend. Nothing but `BelayApp` may import AppKit/SwiftUI.

> **As built.** One SwiftPM package with one target per module, not six packages
> (PROJECT_STATE D1), and no `BelayHelperCLI` (D3 — the command shim was cut once
> async HTTP hooks were proven to work).

```
Belay/
├── project.yml                 XcodeGen source of truth
├── Packages/BelayKit/
│   ├── Package.swift           the target graph *is* the dependency rule
│   └── Sources/
│       ├── BelayCore/          domain types, SignalBus, ActivityCoordinator, Clock
│       ├── BelayPower/         IOKit assertions, power source, sleep/wake events
│       ├── BelayProviders/     ClaudeCode + Codex + Cline + Copilot + Generic (presets ride on Generic)
│       ├── BelayHookBridge/    loopback receiver + hook installer + backup/restore
│       ├── BelaySettings/      typed preferences, migration, defaults
│       ├── BelayChannel/       DistributionChannel, UpdateChannel
│       └── BelaySupport/       Log, FileAccess abstraction
├── Sources/BelayApp/           delegate, status item, panel, settings, ProviderHost
├── Tests/BelayAppTests/        app-level tests (module suites live in the package)
├── Resources/                  Assets.xcassets, Entitlements
└── scripts/                    build-local.sh, test.sh, perf-soak.sh, release.sh, …
```

### Dependency rule

```
BelayApp ──▶ BelayCore ──▶ BelaySupport
   │            ▲   ▲
   ├──▶ BelayPower    │
   ├──▶ BelayProviders┘
   ├──▶ BelayHookBridge
   └──▶ BelaySettings
```

`BelayCore` knows nothing about IOKit, the filesystem, or Claude. It receives
signals and emits decisions. That's what makes the state machine unit-testable
in milliseconds with zero I/O.

## Data flow

```
 ┌───────────────────┐
 │ ClaudeCodeProvider│──┐
 ├───────────────────┤  │
 │ CodexProvider     │──┤
 ├───────────────────┤  │   ActivitySignal
 │ ClineProvider     │──┼──────────────▶ SignalBus ──▶ ActivityCoordinator
 ├───────────────────┤  │
 │ CopilotProvider   │──┤                                     │
 ├───────────────────┤  │                                     │ AwakeDecision
 │ GenericProvider   │──┤                                      ▼
 ├───────────────────┤  │                          PowerAssertionController
 │ hook bridge .exact│──┘                                     │
 └───────────────────┘                                        │
 UI (StatusItem, Panel, Settings) ◀── @Observable AppState ◀───┘
```

## Core types

```swift
public struct SessionID: Hashable, Sendable { public let rawValue: String }

public enum ProviderID: String, Sendable, CaseIterable, Codable {
    case claudeCode, codex, cline, copilot, generic
}

public enum SessionActivity: Sendable, Equatable {
    case working            // model or tool is running
    case awaitingUser       // blocked on a permission prompt or question
    case idle               // turn finished, nothing running
    case ended              // session closed
}

public struct ActivitySignal: Sendable, Equatable {
    public let provider: ProviderID
    public let session: SessionID
    public let activity: SessionActivity
    public let workspace: String?     // display name, e.g. the project folder
    public let timestamp: Date
    public let confidence: Confidence // .exact (hook) | .inferred (filesystem/process)
}

public enum AwakeDecision: Sendable, Equatable {
    case release
    case hold(reason: String, until: Date)   // `until` = assertion timeout deadline
}
```

`AwakeDecision.hold` carrying an explicit deadline is deliberate: the decision
layer, not the IOKit layer, owns the safety timeout, and tests can assert on it.

## The coordinator

`ActivityCoordinator` is a plain actor with **no** dependencies on time-of-day,
Foundation timers, or I/O. It takes a `Clock` protocol so tests can drive years
of simulated time in a millisecond.

```swift
public protocol Clock: Sendable {
    var now: Date { get }
    func sleep(until: Date) async throws
}
```

Responsibilities:
- maintain `[SessionID: SessionState]` with per-session TTL eviction
- fuse signals of differing confidence (exact beats inferred for the same session)
- run the grace-period timer after the last session goes idle
- apply policy: mode (auto/always/off), max duration cap, battery guard
- emit `AwakeDecision` on change **only** — no repeated emissions

### State machine

```
                  ┌──────────────── any session .working ──────────────┐
                  │                                                     ▼
   ┌────────┐  arm  ┌────────┐   session .working    ┌─────────┐   all idle   ┌────────────┐
   │  Off   │──────▶│ Armed  │──────────────────────▶│ Working │─────────────▶│ CoolingDown│
   └────────┘       └────────┘                       └─────────┘              └────────────┘
        ▲                ▲                              │   ▲                       │
        │                └──────── grace elapsed ───────┼───┼───────────────────────┘
        │                                               │   │
        │                            .awaitingUser ─────┘   └──── new work
        │                                   │
        │                                   ▼
        │                          ┌───────────────┐   awaitingUser budget expires
        └───── user turns off ─────│ AwaitingUser  │──────────────▶ Armed (releases)
                                   └───────────────┘
```

An expired awaiting-user budget releases **directly** rather than routing through
CoolingDown: PRD R7 calls the budget a bounded window after which Belay gives up,
and stacking another grace period on a 15-minute wait contradicts that
(PROJECT_STATE D8).

`Armed` and `Working` both mean "Belay is running in auto mode"; only `Working`
and `AwaitingUser` hold an assertion. `CoolingDown` still holds the assertion —
that *is* the grace period — and is what prevents the Mac dozing off between two
tool calls.

## Concurrency model

- Swift 6 language mode, strict concurrency checking **on**, warnings as errors.
- `ActivityCoordinator` and `PowerAssertionController` are actors.
- Providers are actors that expose `AsyncStream<ActivitySignal>`.
- Everything UI-facing is `@MainActor` and driven by a single `@Observable`
  `AppState` that mirrors coordinator output. UI never reaches backwards.
- No `DispatchQueue` unless you're bridging a C callback (FSEvents), and then
  hop to the actor immediately.
- Timers: use `Task.sleep` on the injected clock, or `DispatchSourceTimer` with
  a generous **leeway** (≥ 10% of interval) so the scheduler can coalesce wakeups.
  Never `Timer.scheduledTimer` with a 1-second interval; that alone blows the
  CPU budget.

## Extensibility contract

Adding a provider = one new type conforming to:

```swift
public protocol ActivityProvider: Actor {
    nonisolated var descriptor: ProviderDescriptor { get }
    var availability: ProviderAvailability { get async }  // .ready | .needsSetup | .unavailable
    var signals: AsyncStream<ActivitySignal> { get }
    func start() async throws
    func stop() async
}
```

`id` comes from `descriptor` via an extension. Everything the settings pane needs
— display name, summary, SF Symbol, whether the provider offers precise
detection — travels in `ProviderDescriptor`, so the pane is generated rather than
hand-written per provider.

There is no `ProviderRegistry`: `Sources/BelayApp/ProviderHost.swift` owns the
providers and the bus (PROJECT_STATE D13), and is the one app-layer file that a
new provider touches.
If adding a provider requires touching more than two files outside its own
folder, the abstraction is wrong — fix the abstraction.

## Logging

`BelaySupport.Log` wraps `os.Logger` with subsystem `com.<org>.belay` and
categories per module. Use signposts around detection and assertion changes so
Instruments traces are readable. **Never log transcript content, prompts, file
paths inside user projects, or session IDs at default level** — session IDs are
`.private` in the format string.
