# BelayProviders

Where activity signals come from when nobody has configured anything. This is
Tier A (transcript watching) and Tier C (process presence) — everything here is
`.inferred`; `.exact` comes from `BelayHookBridge`.

Four providers are first-class: `ClaudeCodeProvider`, `CodexProvider`,
`ClineProvider` and `CopilotProvider`. Each reads its agent's own session files
for explicit turn markers. Claude Code is the template — `FileEventStream` wraps
FSEvents, `TranscriptCursor` reads only what was appended, `TranscriptClassifier`
decides what the appended bytes mean, and `ProcessPresence` reads
`~/.claude/sessions/<pid>.json` to notice a session whose process is gone —
and the others (`CodexRollout`, `ClineSessionFile`, `CopilotEvents`) follow the
same shape against `~/.codex/sessions`, `~/.cline/data/sessions` and
`~/.copilot/session-state`. Claude, Codex and Cline additionally have an exact
tier through `BelayHookBridge`; Copilot's event log has no turn-end hook, so it
is inferred-only.

`GenericProvider` covers every agent with no bespoke support: one actor hosting
any number of `GenericTarget`s, each watching a folder, requiring a named process
to be alive, or accepting a routed webhook. `GenericPreset.all` is the shipped
list (Gemini CLI, OpenCode, Aider, Cline (VS Code), Pi) — Codex and Copilot are
deliberately absent, each having a first-class provider — and adding to it is one
array element, no new type and no UI change. `ProcessRoster` enumerates the
user's processes with `sysctl(KERN_PROC_UID)` for the liveness half of that.

**Depends on:** `BelaySupport` and `BelayCore`. Filesystem access goes through
`FileAccessProvider`, so nothing here knows whether it is sandboxed.

## Things that might surprise you

**Growth is the signal; parsing is a refinement on top.**
`TranscriptDelta.indicatesWrite` is `bytesRead > 0 || didReset`, and `ingest`
falls back to `.working` whenever the classifier returns `nil`. That ordering is
the entire mitigation for risk R1 — Claude Code's record format will change, and
when it does, a file that grew is still a file that grew. Never make the primary
signal depend on JSON.

**The classifier scans backwards for the last *conversational* record.** The
literal tail of a finished transcript is a metadata record (`last-prompt`, `mode`,
`custom-title`) far more often than not, and records are not ordered by timestamp.
`docs/03`'s "classify the tail record" produced no signal for 12 of 14 real
transcripts; this rule got all 14 right. Unknown `type` values and an unknown
`stop_reason` both resolve to `.working`, because guessing `.idle` cuts a live
turn short while guessing `.working` costs at most one idle window.

**`.working` is re-emitted deliberately; `.idle` is not.** The coordinator treats
a repeated `.working` as a heartbeat and needs the fresh timestamp. A repeated
`.idle` is just noise, so `report` suppresses it.

**Startup is the dangerous moment, not steady state.** There were 45 transcripts
on the machine this was built against. Anything untouched for longer than
`staleAtStartupAfter` (10 min) is not followed at all; anything merely old is
followed but silent until it actually moves. Cursors seed at EOF — history is not
ours to read. A transcript that appears *while* Belay is running is news, so that
one seeds from the tail window instead.

**A transcript is never read from offset 0 after the first sighting.** Files reach
82 MB in the wild; a naive re-read would move about 100 MB per FSEvent. The cursor
keeps `(inode, offset)`, caps a delta at 256 KB, and resyncs to the last 64 KB
beyond that — after a wake from sleep the backlog is history.

**Tier C never produces `.working`.** A live process says nothing about whether it
is busy. It exists only to end sessions early, and it only considers sessions the
provider is already following. It uses `kill(pid, 0)` and treats `EPERM` as alive:
only `ESRCH` proves a process is gone.

**One `GenericProvider` actor hosts every configured target, not one actor
each.** `ProviderID` is the identity the bus and the settings pane work in and
there is exactly one `.generic` case, so N targets share one 5 s ticker and one
FSEvents stream per distinct folder rather than N of each. Its webhook reports are
`.inferred` like everything else here: a local caller asserting "I am busy" is a
hint from an unverified tool and must never outrank an `.exact` idle from the hook
bridge.

**Workspace names from the directory are a lossy fallback.** The project directory
under `~/.claude/projects` is the cwd with both `/` and `.` flattened to `-`.
Taking the last segment is good enough for a menu bar row; reversing it into a
path is forbidden. Tier C replaces it with the real `cwd` as soon as it sees the
session.
