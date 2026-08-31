# 03 – Detection

> This is the hardest and most valuable part of the product. Read it twice.
> **Verify every factual claim here against the live system and the current
> vendor docs before implementing** – the findings are in `docs/DISCOVERY.md`.

## What we are *not* doing, and why

**Not the Anthropic API.** The API has no knowledge of a local Claude Code
process. There is no "is my CLI busy" endpoint, and asking the API would cost
money to learn nothing. Any design that requires the user to paste an API key
is wrong. Say so in the README FAQ – users will ask.

**Not CPU sampling.** "Is the `claude` process above X% CPU" is a heuristic that
fails in both directions: an agent waiting 90 seconds on a network response uses
no CPU but is very much working, and a language server in the same tree can peg
a core while nothing is happening. Use process presence as *context*, never as
the primary signal.

**Not screen/keyboard idle.** That's what macOS already does. We're adding
information macOS doesn't have.

## Two tiers

### Tier A – Transcript watcher (default, zero setup, ships in M2)

Claude Code persists each session's conversation to a JSONL transcript on disk.
Hook payloads reference it as `transcript_path`, and the files live under
`~/.claude/` (confirm the exact layout during discovery – historically
`~/.claude/projects/<url-encoded-cwd>/<session-uuid>.jsonl`).

The file grows as the turn streams. That gives us a strong, dependency-free
activity signal:

```
FSEvents on ~/.claude  (kFSEventStreamCreateFlagFileEvents, latency 1.0s,
                        kFSEventStreamCreateFlagNoDefer)
   │
   ├─ file changed → look up (or create) a TranscriptCursor for that path
   │                 read only from lastOffset to EOF (never re-read the file)
   │                 parse the trailing complete JSONL records
   │
   └─ emit .working on growth; classify the tail record to detect turn end
```

Implementation notes that matter:

- **Never read the whole file.** Keep `(inode, lastOffset)` per session. Seek,
  read the delta, parse complete lines only, stash any partial trailing line.
  A long session transcript is megabytes; re-reading it on every event is how
  you end up with the CPU profile of a cryptominer.
- **Handle truncation and rotation** – if current size < lastOffset, reset the
  cursor and re-sync from the tail.
- **Cap the read window.** If the delta exceeds ~256 KB (e.g. after a wake from
  sleep), skip to the last 64 KB and resync; we care about *now*, not history.
- **Parse minimally.** You need the record `type`/`role` and possibly a
  `stop_reason`-like field. Decode into a small `TranscriptRecord` struct with
  only the fields you use, and be permissive: unknown record types are ignored,
  not errors. The format will change; the watcher must degrade to
  "file grew → something is happening" rather than break.
- **Idle inference.** Emit `.idle` for a session when (a) the tail record looks
  like a completed assistant turn, **or** (b) no growth for `inferredIdleAfter`
  (default 45 s). Both paths feed the same coordinator grace period, so the
  effective wake-tail is ~2 minutes worst case. That is the correct trade.
- **A running tool call is not idle** (shipped in 1.6.2). Neither path above can
  see one: a command that runs for half an hour writes nothing at all, so the
  transcript looks finished within the minute. Tier B closes it exactly – an
  open `PreToolUse` bracket outranks the file watcher until the tool returns
  (`SessionState.openToolCallSince`, bounded by `openToolCallBudget`). Tier C
  closes it approximately, for builds with no hooks: the busy-child probe walks
  the agent's whole descendant tree, because the shell that owns the tool call
  outlives every turn and the process actually working is below it.
- **A waiting turn is not idle** (shipped in 1.3). When the tail is an open
  user turn or the CLI's own API-error record, the agent is waiting out a
  retry against an overloaded model, not resting – exactly when the Mac must
  stay awake. Silence then keeps `.working` under a longer, bounded grace
  (15 min, heartbeats hold the coordinator's session TTL open). If the grace
  runs out with no answer, the session ends as *went quiet* – reported as a
  stall, never as a finished turn (1.3.1).
- **Ignore stale files at startup.** On launch, seed cursors at EOF and treat
  any file untouched for > 10 minutes as an ended session. Otherwise Belay will
  "discover" 40 old sessions and hold the Mac awake on boot.
- **Sandbox**: FSEvents on `~/.claude` requires the user to grant access to that
  folder once via `NSOpenPanel`, stored as a security-scoped bookmark. See
  `docs/06-DISTRIBUTION.md`. The onboarding flow must make this feel like one
  obvious click, with a plain-language explanation of what we read and don't.

- **Codex rollouts** (shipped in 1.3.2). Codex persists explicit turn markers
  into `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` – `task_started` /
  `task_complete` in `event_msg` records – so `CodexProvider` reads exact turn
  edges instead of inferring them, with the same open-turn grace and
  went-quiet ending as Claude Code. Verified on a live install (0.148);
  compressed `.jsonl.zst` history is skipped, `session_meta.cwd` names the
  workspace.

Confidence of Tier A signals: `.inferred`.

### Tier B – Hook bridge (opt-in, exact, ships in M3)

Claude Code fires lifecycle hooks configured in `~/.claude/settings.json`.
Every hook receives a JSON envelope on stdin containing at minimum
`session_id`, `transcript_path`, `cwd` and `hook_event_name`. Recent versions
also support HTTP hooks, which receive the same JSON as a POST body – verify
this during discovery, and prefer it if available.

Map events to activity:

| Event | Signal |
|---|---|
| `SessionStart` | session registered, `.idle` |
| `UserPromptSubmit` | `.working` |
| `PreToolUse` / `PostToolUse` | `.working` (heartbeat – this is what keeps long tool runs alive) |
| `Notification` | `.awaitingUser` (permission prompt / question) |
| `Stop` | `.idle` |
| `SubagentStop` | no signal since 1.3.3: it trails the turn's own `Stop` by seconds, and one trailing heartbeat pinned the Mac for the exact-freshness window. The parent's events and the subagents' watched transcripts carry the hold |
| `SessionEnd` | `.ended` |

Two delivery mechanisms; implement the HTTP one if supported, keep the command
shim as the fallback.

**B1 – HTTP receiver (preferred).** Belay runs an `NWListener` bound to
`127.0.0.1`, writes the port and a random per-install bearer token to
`~/Library/Application Support/Belay/bridge.json`, and registers hooks pointing
at `http://127.0.0.1:<port>/hook`. Requests without the token are dropped. Bind
to loopback only, never `0.0.0.0`.

The port is the one thing a running agent cannot follow, because its settings
file was written once and is read per hook call. So the receiver keeps it: on
launch it asks for the port already in `bridge.json`, and retries it four times
a quarter-second apart, which is what an update needs: the outgoing instance
is still holding the socket when the new one binds. A first run picks from
41000–42999. Not the ephemeral range: that is where macOS puts outgoing
connections, so a port recorded there can be taken by anything else on the
machine while Belay is closed. Only when the quiet band refuses too does it
settle for whatever is free, because a bridge on an awkward port beats no
bridge. Every outcome is logged (`bridge up port=N`, `bridge port busy,
retrying`, `bridge did not start: …`).

**Direct build only.** Under the sandbox this needs
`com.apple.security.network.server`, and it could not work there in any case:
the installer edits `~/.claude/settings.json` and the sandbox home is the app's
container. `PreciseDetection.isSupported` is false in the App Store build, so
nothing binds and the control is not shown. See `BLOCKERS.md (git history)` B3.

**B2 – Command shim (fallback).** Ship a tiny `belay-hook` executable in
`Belay.app/Contents/Helpers/`. It reads stdin, connects to a Unix domain socket,
writes, and exits. Hard rules:

- Total budget **50 ms**, enforced with a socket timeout.
- **Always `exit 0`.** A non-zero exit from a hook can block or disrupt Claude
  Code. Belay must be incapable of breaking the user's agent. This is the single
  most important line in this document.
- No dynamic dependencies, no JSON re-serialisation – forward the raw bytes.
- Self-heal: on every app launch, check the path recorded in `settings.json`
  still points at the current bundle; rewrite it if the app was moved.

**Installing hooks safely.** Belay edits the user's `~/.claude/settings.json`.
That file is precious. Therefore:

1. Explicit user action in Settings → Providers → "Enable precise detection",
   with a diff preview of exactly what will be added.
2. Timestamped backup to `~/Library/Application Support/Belay/backups/` first.
3. Read → parse → merge → atomic write (write to temp in the same directory,
   `FileManager.replaceItem`). Preserve key order and formatting as far as
   `JSONSerialization` allows; if the file has comments or is otherwise not
   plain JSON, **do not write** – show the snippet and a copy button instead.
4. All Belay-owned entries carry an identifiable marker so uninstall is exact.
5. One-click "Remove integration" that restores cleanly, plus a documented
   manual removal procedure in the README for when someone deletes the app first.

Confidence of Tier B signals: `.exact`.

### Tier C – Process presence (supporting context, cheap, M2)

> **As built.** Discovery found `~/.claude/sessions/<pid>.json`, which maps
> pid → sessionId → cwd directly, so for Claude Code there is nothing to
> enumerate: read the file and call `kill(pid, 0)`. `sysctl(KERN_PROC_UID)` is
> used only by the generic provider's watch-a-process-name option, where no such
> file exists. See `docs/DISCOVERY.md` §1.1.

Every 15 s (coalesced timer, ±3 s leeway), check whether the agent's process is
still alive. Use it only to:

- expire sessions whose process is gone (crash, `kill`, terminal closed) – this
  is the safety net that stops a dead session pinning the Mac awake
- decide whether a provider is "installed" for the UI's availability state

Do **not** derive `.working` from it. Under App Sandbox, reading other processes'
full argument vectors via `KERN_PROCARGS2` may be restricted; treat argument
inspection as best-effort and never depend on it for correctness.

## Fusion rules

For a given session, the coordinator prefers:

1. an `.exact` signal newer than `hookFreshnessWindow` (default 5 min)
2. otherwise the newest `.inferred` signal
3. a session with **no** signal for `sessionTTL` (default 10 min) is evicted

When Tier B is active for a session, the transcript watcher for that session
downgrades to a heartbeat-only role – it can keep `.working` alive but cannot
override an `.exact` `.idle`. This prevents the classic bug where a hook says
"done", a trailing disk flush says "still writing", and the two fight forever.

## Watched folders beyond the default home

Every built-in agent can relocate – `CLAUDE_CONFIG_DIR`, `CODEX_HOME`,
`CLINE_DIR`, `COPILOT_HOME` – and multi-profile setups run several at once
(issue #4). A GUI app cannot read another shell's environment, so the folders
arrive by being picked: each tile's menu (the slider button, or right-click)
carries "Watched Folders" with the default home, any added folders, and "Add
Folder". One provider instance runs per (agent, folder); nothing below the app
layer changes. Extras read through the picked-folder grants, so the open panel
that chose the folder is the sandbox grant in the MAS build. Precise Detection
covers every watched folder – hooks live inside a root, so enabling installs
into each, an added folder is installed into when already enabled, and a
removed folder takes its Belay-marked hooks with it. The direct build also
suggests sibling profiles it finds next to the default home (`~/.claude-work`
beside `~/.claude`); the sandboxed build cannot enumerate the home folder, so
it never suggests.

## Other providers

**Cline (shipped first-class in 1.5.0).** `ClineProvider` reads the per-session
state files under `~/.cline/data/sessions/<id>/<id>.json`: the `status` field
says `running`/`idle`/`completed`/`cancelled`/`failed` outright, and the
sibling `messages.json`'s growth is the heartbeat. One caveat is load-bearing:
a Ctrl-C leaves `status` stuck on `running` forever, so the idle sweep – not
the status – has the last word on silence. Team mode writes
`<agent>__<suffix>.messages.json` files inside the parent session's folder;
those become child sessions with `parent`/`kind` set, presented under their
session like Claude Code subagents. The exact tier is per-event hook scripts
in `~/.cline/hooks` (`TaskStart.sh` … `SessionShutdown.sh`), payload on
stdin; the event name rides in the URL because the payload's `hookName`
speaks internal names. Verified live 2026-08-24 against cline 3.0.57.

**Copilot CLI (first-class in 1.6.0).** `CopilotProvider` follows
`~/.copilot/session-state/<uuid>/events.jsonl`: an append-per-event stream
with explicit `assistant.turn_start` / `assistant.turn_end` markers and a
`session.shutdown` on a clean exit – the Codex shape with even less guessing.
A Ctrl-C mid-turn writes no closing marker, so the idle and dead-process
sweeps have the last word there, same as Cline. Copilot ships hooks of its own
(`.github/hooks/*.json`) but no turn-end event, so the event log beats them
and there is no exact tier. One overlap to know about: Copilot has its own
`keepAlive` setting (off/on/busy) that pins the Mac from inside the CLI;
harmless beside Belay, just redundant. Verified live 2026-08-24 against
copilot-cli 1.0.80.

**Codex (shipped first-class in 1.3.2).** `CodexProvider` follows the session
rollouts – see "Codex rollouts" above. The `notify` hook in
`~/.codex/config.toml` was verified empirically and rejected as Belay's
channel: on a machine running the Codex desktop app it is already taken by
their own client, and it is a single global value we must not clobber. Codex's
Claude-style hook system (stable, `~/.codex/hooks.json`) is the exact tier and
shipped in 1.5.0 (`CodexHookInstaller`, `CodexTrust`, `CodexConfigDocument`); it
sits behind a per-hook trust review, which Belay satisfies by reading the trust
hashes from `codex app-server hooks/list` and writing them into `config.toml`.
The rollout watcher remains the always-on Tier A beneath it.

**Generic provider (P1).** Configurable by the user, covers everything else
including DeepSeek-backed tools:
- watch a folder for modifications (path picked via `NSOpenPanel`)
- watch for a process name being alive *and* its transcript path changing
- accept a local webhook: `curl -s localhost:<port>/hook?token=…&state=working`
  documented in the README so any tool with a shell hook can integrate in one line

Ship the generic provider with 2–3 preset templates (Aider, Gemini CLI, Cline)
that are just pre-filled configurations, not code.

## Testing detection

Detection cannot be verified by unit tests alone. Build `scripts/fake-agent.sh`:
a script that writes plausible JSONL records to a temp directory at a
configurable rate, pauses, resumes, dies without cleanup, and truncates its own
file. Run the full pipeline against it in CI. Then verify against a real Claude
Code session manually and record the results in `docs/DISCOVERY.md`.
