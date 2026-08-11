# 003 — Two-tier detection: file growth first, hooks for precision

**Status:** accepted, implemented in M2 (Tier A, Tier C) and M3 (Tier B)

## Context

Vigil has to answer one question — is a local coding agent working right now? —
and it has to keep answering it correctly after Claude Code ships a release that
nobody told us about.

There is no API for this. The Anthropic API has no knowledge of a local `claude`
process, so any design that needs a pasted key is solving a different problem.
CPU sampling fails in both directions: an agent waiting ninety seconds on a
network response uses no CPU and is very much working, while a language server in
the same tree can peg a core while nothing is happening. Screen and keyboard idle
is what macOS already does; we are here to add information macOS does not have.

That leaves what Claude Code writes down. It appends every session's conversation
to a JSONL transcript under `~/.claude/projects/`, and it can fire lifecycle
hooks configured in `~/.claude/settings.json`. Neither is a public API contract,
and risk **R1** says plainly that both will change.

The two sources have opposite failure modes, which is the whole reason there are
two of them. The transcript is always there and needs no setup, but it can only
report what has been written; it cannot distinguish "the agent finished" from
"the agent is blocked on a permission prompt", because in both cases the file
simply stops growing. Hooks say exactly what happened and when, but they are
opt-in, they require editing the file the user cares about most, and they are the
part most likely to be broken by a CLI upgrade.

## Decision

Three signal sources, fused by confidence rather than by arrival order.

**Tier A — the transcript watcher, `.inferred`, on by default, no setup.**
FSEvents on `~/.claude/projects` with file-level events; a per-session cursor
keeping `(inode, offset)`; a read of the delta and nothing else.

The primary signal is **that the file grew**. Not what it says — that it grew.
`TranscriptDelta.indicatesWrite` is `bytesRead > 0 || didReset`, and
`ClaudeCodeProvider.ingest` falls back to `.working` whenever the classifier
returns nothing. This is the entire mitigation for R1, and it is deliberately
placed below any JSON parsing so that no change to the record shape can take it
away. A format we have never seen still moves bytes.

Structural parsing is a refinement layered on top, and its rule is **the last
*conversational* record in the delta**, not the last record. Discovery is
unambiguous about why. Across 13 finished sessions on the host, the literal last
line of the file was `last-prompt` six times, `mode` three times, `custom-title`
twice, `ai-title` once, and an actual assistant turn exactly once: Claude Code
appends metadata *after* the turn completes. Records are not ordered by timestamp
either — a live tail read `14:28:21, 14:28:21, 14:28:30, 14:28:27, 14:28:31, …`.
So the classifier scans backwards past `attachment`, `last-prompt`, `mode`,
`custom-title`, `ai-title` and `queue-operation`, takes the last `assistant` or
`user` record, and maps `end_turn`/`stop_sequence` to `.idle` and everything else
— including a `stop_reason` a future CLI invents — to `.working`.

That correction was replayed over 14 real transcripts ranging from 0.01 MB to
86 MB before it was trusted. The spec's "classify the tail record" produced no
signal at all for 12 of the 14; the reverse-scan rule returned `.idle` correctly
for all 14.

No growth for `inferredIdleAfter` (45 s) infers idle. That number is not
conservatism for its own sake: sampling a live transcript at 1 Hz caught ten
consecutive flat seconds in the middle of a single long tool call, with the agent
unambiguously working. That is risk **R6**, observed rather than theorised, and
it is why 45 s must not be tightened.

**Tier C — process presence, `.inferred`, supporting only.** Every third
five-second tick, `~/.claude/sessions/<pid>.json` is read and each pid tested
with `kill(pid, 0)`. It exists to end sessions whose process is gone, and it
never emits `.working`: a process being alive says nothing about whether it is
busy. It also supplies the real `cwd` for display, which is the only honest
source for a workspace name — the encoded project directory flattens both `/` and
`.` to `-`, and that is lossy enough that reversing it is forbidden.

**Tier B — the hook bridge, `.exact`, opt-in.** An `NWListener` on `127.0.0.1`,
ephemeral port, bearer token, fourteen registered events, every hook written with
`"async": true`. This is the tier that can see `awaitingUser`, and it is the
reason the tier exists at all.

**Fusion.** An `.exact` reading outranks any `.inferred` one while it is newer
than `hookFreshnessWindow` (5 min); after that the file watcher takes over again.
Crucially, the two readings are kept in separate slots on `SessionState` rather
than collapsed on arrival, and `effectiveActivity(now:freshness:)` applies the
rule against the current time on every evaluation. Collapsing early produces the
classic bug where a hook says "done", a trailing disk flush says "still writing",
and whichever landed last wins forever.

### The command shim is cut

`docs/03` B2 specifies a `vigil-hook` executable in `Vigil.app/Contents/Helpers/`
as the fallback delivery path: reads stdin, writes to a Unix socket, 50 ms
budget, and an absolute "always `exit 0`" rule that the document itself calls its
single most important line.

It was cut before it was written, because discovery proved it unnecessary.
Configured against a scratch project and a real Claude Code turn, `type: "http"`
hooks fired against a loopback listener, a custom `Authorization: Bearer` header
arrived verbatim, and `"async": true` was accepted without the turn waiting on
the response.

An async HTTP hook cannot block or slow Claude Code *by construction*. There is
no exit code to get wrong and nothing to wait on. The shim, by contrast, costs a
second executable in the bundle, a Unix socket, a 50 ms budget to police, and the
one failure mode in this project that could actually break the user's agent.
`docs/00-INVARIANTS.md` invariant 5 is satisfied more strongly by deleting the component than
by hardening it.

The receiver protocol is plain HTTP POST either way, so if a future Claude Code
drops `http` hooks the shim can come back without redesigning anything.

## Consequences

- **The default experience needs no configuration and no trust.** Vigil detected
  a real session on this machine at first run and held with
  `Details: An agent is working in Vigil`; a second concurrent session aggregated
  to `2 agent sessions are working` and resolved back down on its own.
- **A format change degrades rather than breaks.** Worst case, structural
  classification stops contributing and idle detection falls back entirely to the
  45 s no-growth rule. The tail gets longer; the app keeps working. Nothing in
  the parse path can throw a session away — unknown `type` values are ignored,
  and a `message` field of the wrong shape loses the field, not the record.
- **The idle tail is about two minutes.** 45 s of idle inference plus the
  coordinator's 90 s grace. That is the correct trade in a product where sleeping
  sixty seconds too early kills a job and staying awake sixty seconds too long
  costs nothing.
- **Tier A alone cannot say "an agent is waiting for you."** A permission prompt
  looks exactly like a finished turn from the outside: the file stops growing and
  nothing else happens. Without hooks, a blocked session simply ages out through
  the grace period, and the "an agent is waiting for you" notification — which
  risk R8 names as the thing that gives anyone a reason to install this app —
  never fires. That is not a flaw in Tier A, it is the boundary of what a file
  watcher can know, and it is what makes enabling hooks worth asking for.
- **Cost: three sources to keep straight.** The confidence split, the freshness
  window and the separate exact/inferred slots are all there to stop them
  fighting, and all three are covered by the coordinator suite plus the
  end-to-end integration tests.
- **Cost: two watchers running at once when hooks are installed.** Cheap in
  practice — FSEvents costs nothing while quiet, the sweep is one 5 s coalesced
  timer, and active CPU measured 0.072% against a 1.0% budget.
- **Never reading a whole transcript is load-bearing, not an optimisation.**
  Files on the host reached 82 MB across 45 transcripts; a naive re-read on every
  FSEvent would move roughly 100 MB per event. The cursor caps a delta at 256 KB
  and resyncs to the last 64 KB beyond that, because after a wake from sleep the
  backlog is history and we care about now.

## Alternatives considered

**Hooks only.** Precise, cheap, and it makes the first-run experience "edit this
config file before the app does anything". It also puts the one component that
can damage `~/.claude/settings.json` on the critical path for every user rather
than only for those who opt in. A utility whose value proposition is "I will
quietly do the right thing" cannot open with a configuration chore.

**Transcript only.** Zero setup and no writes to anything of the user's, but it
cannot distinguish blocked from finished, which forfeits the notification that
gives people a reason to install Vigil at all. It also has no answer for a long
silent tool call other than a longer and longer idle window.

**Classify the literal tail record**, as `docs/03` originally specifies. Measured
and rejected: it yields no signal for 12 of 14 real transcripts, because Claude
Code writes metadata after the turn ends. This is the clearest case in the
project of a spec that was reasonable to write and wrong in fact.

**`KERN_PROCARGS2` for Tier C**, also from `docs/03`, which warns in the same
breath that it may be restricted under sandbox. Unnecessary:
`~/.claude/sessions/<pid>.json` maps pid to session id to cwd outright, so Vigil
never inspects another process's argument vector. Better, and better-behaved.

**Polling the transcript directory instead of FSEvents.** Discovery left FSEvents
on `~/.claude` unverified after a throwaway probe crashed, and polling was the
standing fallback. The probe turned out to be the bug — it crashed against a
scratch directory too. Built properly, the stream starts in 3 ms across 45
transcripts in 19 project directories and TCC does not interfere. Polling would
have cost a wakeup budget for nothing.
