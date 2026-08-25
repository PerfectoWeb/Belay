# 01 — Product Requirements

## Problem

Developers run long autonomous agent tasks (Claude Code, Codex CLI, and
similar) that take anywhere from 40 seconds to two hours. macOS idle sleep
doesn't know the difference between "user walked away" and "an agent is
mid-refactor". Today people solve this two ways, both bad:

- **Set sleep to Never.** The Mac now burns power 24/7 and the user has to
  remember to change it back. Nobody remembers.
- **Leave the Mac awake manually / `caffeinate` in a terminal.** Requires a
  decision every single time, and the terminal window becomes load-bearing.

The cost of getting it wrong is asymmetric: sleeping too early kills a
long-running job silently and wastes tokens and wall-clock time. So users
over-correct and never sleep. That's the behaviour we're fixing.

## Solution

A menu bar app that watches local agent activity and holds a system-sleep
assertion only while an agent is genuinely working. When every tracked session
goes idle for a short grace period, the assertion drops and macOS resumes its
normal, user-configured sleep behaviour. The user's System Settings are never
modified. (1.3 added the sole exception, opt-in and direct-channel only: the
lid hold's privileged helper raises the kernel's own sleep switch while work
runs, and clears it by itself — see the ROADMAP plan.)

## Target user

A developer on macOS 14+ who runs Claude Code regularly, has idle sleep set to
something short (5–20 min), and works overnight or unattended.

## Core requirements

### R1 — Zero-configuration detection
Belay must detect Claude Code activity out of the box, without the user
installing anything, editing config files, or supplying credentials. A more
precise, opt-in integration (hooks) may be offered on top, but must never be
required.

### R2 — Correctness over aggressiveness
False negatives (letting the Mac sleep mid-task) are far worse than false
positives (staying awake 60 s longer than needed). Tune the grace period
accordingly — default 90 s — but never let a stale session pin the Mac
indefinitely (see the TTL invariant).

### R3 — All sessions, aggregated
The Mac stays awake while **any** tracked session is working. The panel shows
each session individually (project folder name, state, elapsed time) so the
user can see what's holding things open. Per-session opt-out is a v1.1 feature.

### R4 — Manual override always available
Three modes, switchable from the menu bar in one click:
- **Auto** (default) — awake iff an agent is working
- **Always on** — a plain caffeinate-equivalent, with optional duration
  (30 min / 1 h / 2 h / until turned off)
- **Off** — Belay holds nothing; the icon reflects this unambiguously

### R5 — Safety rails
- Hard cap on continuous awake time (default 4 h, configurable, "unlimited" allowed)
- Battery guard: on battery below N% (default 20%), release and stop re-arming
- Respect Low Power Mode as a signal to be conservative (configurable)
- Display sleep is **allowed** by default; we only prevent *system* sleep

### R6 — Invisible when idle
Menu bar only (`LSUIElement`), no Dock icon, no windows on launch. Monochrome
template icon that adapts to light/dark and to the Tahoe menu bar automatically.
Icon state must be readable at a glance:
- idle/armed → outline moon
- working → filled indicator + optional subtle badge
- off → outline with a slash
- awaiting user input → distinct third state (see R7)

### R7 — "Claude needs you" notification (differentiator)
When an agent is blocked waiting for a permission prompt or user input, that is
*not* work — but sleeping then is also unhelpful. Belay surfaces a native
notification ("Claude Code is waiting for your input — project *foo*") and
enters an `awaitingUser` state that keeps the Mac awake for a bounded window
(default 15 min) before giving up. This single feature is worth more to users
than everything else combined; it turns a utility into a product.

### R8 — Multi-provider, extensible
Claude Code is P0 and must be excellent. Codex was P1 and shipped first-class
in 1.3.2, the day its rollout format was verified on a real install; Cline
followed in 1.5.0 and Copilot CLI in 1.6.0. A generic provider (watch a
folder / watch a process name / accept a local webhook) covers Gemini CLI,
OpenCode, Aider, Pi and anything future without a code change. A new first-class provider must be addable by writing
one file that conforms to one protocol — `CodexProvider` is the proof.

> On DeepSeek specifically: there is no first-party DeepSeek CLI to hook into.
> DeepSeek is consumed through other tools (Cline, Aider, OpenRouter-backed
> clients). It is therefore served by the generic provider, not a dedicated one.
> Do not build a "DeepSeek provider" that pretends otherwise.

### R9 — Privacy
Belay reads local agent state to determine *whether* work is happening. It must
never read prompt or response **content** beyond the minimum structural fields
needed for state detection, never transmit anything off-device, and never log
transcript contents. This is stated plainly in `SECURITY.md` and in the
onboarding screen. Treat it as a hard product constraint, not a nice-to-have —
it is also the argument that gets the app through App Review.

## Non-goals for v1.0

- Remote/SSH session monitoring
- Wake-on-schedule, or waking a sleeping Mac
- Token/cost tracking, usage dashboards, session history analytics
- iOS companion app
- Preventing sleep on lid close (macOS does not allow this for idle
  assertions — document it in the FAQ instead of faking it). Held until 1.3,
  which shipped it honestly: not an assertion but a privileged helper holding
  the kernel's switch, opt-in, direct builds only, proven with a control run

## Success criteria

- A 2-hour unattended Claude Code run completes with the Mac never sleeping
- Within 2 minutes of the run finishing, `pmset -g assertions` shows no Belay
  assertion and the Mac sleeps on its normal schedule
- Idle CPU indistinguishable from zero in Activity Monitor
- A new user gets value within 30 seconds of first launch, with no setup
