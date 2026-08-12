# Discovery — what the real machine says

Empirical pass run on the host before any implementation code was written.
**Where this file disagrees with `docs/01`–`docs/11`, this file wins.** Every
claim below was observed, not assumed.

Host: macOS 26.4 (25E246) · Xcode 26.6 (17F113) · Swift 6.3.3 ·
Claude Code CLI 2.1.170, running sessions report 2.1.222 · date 2026-08-10.

Toolchain installed during this pass: `swiftlint` 0.65.0, `swift-format` 603.0.0
(`xcodegen` was already present). `create-dmg` is absent — only needed by the
unrun release script.

---

## 1. `~/.claude` layout

```
~/.claude/
├── projects/<path-with-slashes-as-dashes>/<session-uuid>.jsonl   ← transcripts
├── sessions/<pid>.json                                           ← live process map
├── settings.json                                                 ← user settings + hooks
├── backups/ cache/ downloads/ plans/ scheduled-tasks/
├── session-env/ shell-snapshots/ tasks/ telemetry/
└── .last-cleanup
```

**Transcript path scheme confirmed** as the spec guessed: the project directory
name is the absolute cwd with `/` replaced by `-` (note: *not* URL-encoding —
`/Volumes/BASE/Work/Apps/MacOS/Belay` → `-Volumes-BASE-Work-Apps-MacOS-Belay`).
Dots in path components are also mapped to `-`. Since this transform is lossy,
**never try to reverse it** to recover a project path — take `cwd` from the
records or from `sessions/<pid>.json` instead. The workspace display name is the
last path component.

45 transcripts across 19 project directories on this machine. Sizes ranged from
93 KB to **82 MB**. This validates the never-read-the-whole-file rule in
`docs/03` emphatically — a naive re-read would move ~100 MB per FSEvent.

### 1.1 `~/.claude/sessions/<pid>.json` — undocumented, and better than `KERN_PROCARGS2`

Not mentioned anywhere in the spec, and it materially improves Tier C:

```json
{ "pid": 20070, "sessionId": "a6e15a28-…", "cwd": "/Volumes/BASE/…/Belay",
  "startedAt": 1786372058888, "procStart": "Mon Aug 10 14:27:38 2026",
  "version": "2.1.222", "peerProtocol": 1, "kind": "interactive",
  "entrypoint": "claude-desktop", "name": "belay-3d", "nameSource": "derived" }
```

This gives us pid → sessionId → cwd directly, so process-presence liveness needs
no argument-vector inspection at all. `docs/03` Tier C warns that `KERN_PROCARGS2`
may be restricted under sandbox and must never be depended on; with this file we
simply don't need it. The pid and its mapping both come from a file the user has
already granted us access to, so liveness is one `kill(pid, 0)` per session.

**Deviation adopted:** Tier C reads `~/.claude/sessions/` and cross-checks each
`pid` with `kill(pid, 0)`. No `sysctl` enumeration and no argument-vector
inspection are involved for Claude Code at all — the file already names the pid,
so there is nothing to search for. (`sysctl(KERN_PROC_UID)` does appear in
`ProcessRoster`, which serves the generic provider's watch-a-process-name
option; that is a different job.)
Stale files (process gone) are the authoritative "this session is dead" signal —
much faster and more reliable than waiting out the 10-minute TTL.

Caveat: `kind` can be `interactive` or other values; `entrypoint` distinguishes
`claude-desktop` from a plain terminal CLI. Treat both as real sessions.

### 1.2 Subagents get their own transcripts, in a folder named after their session

Found while a workflow of 54 agents was running (2026-08-11). A session that
spawns agents grows a directory beside its own transcript:

```
projects/<project>/<session>.jsonl                                    the session
projects/<project>/<session>/subagents/agent-<id>.jsonl               a Task subagent
projects/<project>/<session>/subagents/workflows/<run>/agent-<id>.jsonl a workflow agent
projects/<project>/<session>/subagents/workflows/<run>/journal.jsonl   the runner's log
```

Three consequences, all of which were bugs until this pass:

1. **The parent is in the path.** The component before `subagents` is the
   spawning session's UUID, and it agrees with the `sessionId` field carried in
   every subagent record — so attribution costs no file read. Subagent records
   also carry `isSidechain: true` and an `agentId`.
2. **The containing folder is not the project.** Taking the last dash-separated
   segment of a transcript's parent folder — correct for a session — gave
   `9d2` for every agent under `wf_60f0c106-9d2`, so 54 agents appeared as 54
   separate projects and crowded the real session out of the panel.
3. **`journal.jsonl` is not a session.** The workflow runner writes it beside
   the agents and it grows for the whole run. Followed, it becomes a phantom
   row nobody started.

A `agent-<id>.meta.json` sits beside each transcript: `agentType`, `spawnDepth`,
and for Task subagents a `description` of the task. Belay reads **`agentType`
only** — the description is a summary of the user's prompt, and the panel is on
screen during screen shares. Workflow agents carry no description.

Observed nesting is one level (`spawnDepth: 1`), but the format does not promise
that, so the UI flattens deeper agents onto the session the user started.

## 2. Transcript JSONL record shape

Record `type` values observed, with frequency across sampled sessions:

| `type` | Conversational? | Notes |
|---|---|---|
| `assistant` | yes | has `message.role`, `message.stop_reason`, `message.content[]` |
| `user` | yes | `message.content[]` is `tool_result` blocks, or a plain string for real user input |
| `attachment` | no | metadata |
| `last-prompt` | no | metadata, `{lastPrompt, leafUuid, sessionId, type}` |
| `custom-title` / `ai-title` | no | metadata |
| `mode` | no | metadata |
| `queue-operation` | no | metadata |

Common envelope on conversational records: `uuid`, `parentUuid`, `sessionId`,
`timestamp` (ISO 8601), `cwd`, `gitBranch`, `version`, `type`, `userType`,
`isSidechain`, `entrypoint`.

`message.stop_reason` distribution over 13 full sessions:
`tool_use` 12759 · `end_turn` 844 · `stop_sequence` 21.

### 2.1 Two findings that break the spec's tail-classification rule

**(a) The last line of the file is usually *not* the assistant turn.**
Tails observed across 13 finished sessions: `last-prompt` ×6, `mode` ×3,
`custom-title` ×2, `assistant`(`end_turn`) ×1, `ai-title`. Claude Code appends
metadata records *after* the turn completes. `docs/03`'s "classify the tail
record" therefore misfires on the majority of real sessions.

**(b) Records are not strictly ordered by timestamp.** Observed in a live tail:
`14:28:21, 14:28:21, 14:28:30, 14:28:27, 14:28:31, 14:28:31, 14:28:31, 14:28:30`.
Metadata records interleave out of order with conversational ones.

**Deviation adopted:** the parser scans the parsed delta for the **last record
whose `type` is `assistant` or `user`**, ignoring metadata types entirely, and
classifies from that:

- `assistant` with `stop_reason == "end_turn"` (or `stop_sequence`) → `.idle`
- `assistant` with `stop_reason == "tool_use"` → `.working`
- `user` carrying `tool_result` blocks → `.working` (tool returned, turn continues)
- `user` with a plain string content → `.working` (a prompt was just submitted)
- nothing conversational in the delta → no classification, but the file grew,
  so `.working` on growth alone still applies

Unknown `type` values are ignored, never errors, exactly as `docs/03` requires.

### 2.2 Growth is bursty, and silence does not mean idle

Sampled the current session's transcript at 1 Hz:

```
t=1s +306683   t=2s +12314   t=3s..t=12s  +0
```

The ten flat seconds were spent inside a single long tool call — the agent was
unambiguously working while the file did not grow by a byte. This is exactly
risk **R6** and it is real, not theoretical. It confirms the
`inferredIdleAfter` = 45 s default is the right order of magnitude and must not
be tightened; combined with the 90 s coordinator grace it gives a ~2 min tail.

## 3. Hooks — verified against the installed binary, not just the docs

`~/.claude/settings.json` on this machine is `{"skipWorkflowUsageWarning": true}`
— it has **no** `hooks` key, so the installer must handle creating the key from
scratch as well as merging into an existing one.

### 3.1 `type: "http"` is supported — and it works

The live reference at <https://code.claude.com/docs/en/hooks> lists five hook
types (`command`, `http`, `mcp_tool`, `prompt`, `agent`). Rather than trust it, I
configured HTTP hooks in a scratch project's `.claude/settings.json`, ran a
Claude Code turn against a local listener on `127.0.0.1:8767`, and captured what
arrived:

```
17:30:19.025 /hook auth=Bearer belay-test-token event=UserPromptSubmit bytes=525
17:30:19.046 /hook auth=Bearer belay-test-token event=SessionEnd     bytes=435
```

Confirmed empirically:

- HTTP hooks fire against a loopback listener.
- A custom `headers: {"Authorization": "Bearer …"}` entry is delivered verbatim
  → **token auth needs no protocol of our own**.
- `"async": true` is accepted and the turn is not blocked on our response.
- The POST body is the JSON envelope.

**Deviation adopted — this is the biggest one in this document.** `docs/03` B1/B2
plan an HTTP receiver *with a `belay-hook` command shim as fallback*, and
`docs/02` lists a `Sources/BelayHelperCLI/` target. With `type: "http"` plus
`async: true` confirmed working, the shim earns nothing: it costs a second
executable in the bundle, a Unix socket, a 50 ms budget to police, and the
`exit 0` hazard that `docs/03` calls "the single most important line in this
document". An async HTTP hook cannot block Claude Code *by construction* — there
is no exit code and no wait. **`BelayHelperCLI` is cut.** Invariant 5 is
satisfied more strongly by deleting the component than by hardening it.

Recorded in `PROJECT_STATE.md`. If a future Claude Code drops `http` hooks, the
shim can come back — the receiver protocol is plain HTTP POST either way.

### 3.2 Envelope fields (observed, not quoted from docs)

```
session_id       c39e2033-0022-4c90-b847-1c93117f8152
transcript_path  /Users/davx/.claude/projects/<encoded-cwd>/<session>.jsonl
cwd              /private/tmp/.../hooktest
permission_mode  default          (not present on every event)
hook_event_name  UserPromptSubmit
prompt           <the user's full prompt text>      ← UserPromptSubmit only
reason           other                              ← SessionEnd only
```

**`UserPromptSubmit` carries the user's entire prompt text.** This is a privacy
landmine given PRD **R9**. The receiver decodes into a struct containing only
`session_id`, `transcript_path`, `cwd`, `hook_event_name`; `prompt` is never
decoded, never logged, never held. Called out explicitly in `SECURITY.md`.

### 3.3 Event set is much larger than the spec assumed

The installed version fires 31 events. The spec's table lists 7. Relevant
additions, and how we map them:

| Event | Belay mapping | Why |
|---|---|---|
| `PermissionRequest` | `.awaitingUser` | **Precise**; the spec's `Notification` is a catch-all that also fires for non-blocking messages |
| `Elicitation` | `.awaitingUser` | Agent is explicitly asking the user a question |
| `ElicitationResult` | `.working` | Answer received, work resumes |
| `PostToolBatch` | `.working` heartbeat | Cheaper than one `PostToolUse` per tool in a batch |
| `SubagentStart` | `.working` heartbeat | Parent turn definitely still running |
| `StopFailure` | `.working` | The turn did **not** end; treating it as `Stop` would release early |
| `TeammateIdle` | ignored in v1.0 | Not a sleep-relevant state |

`Notification` is still mapped to `.awaitingUser` for older CLI versions, but
`PermissionRequest`/`Elicitation` take precedence when both arrive.

`SessionEnd` hooks share a **1.5 s** total budget across all registered hooks —
another reason ours must be `async`.

### 3.4 Hook config structure to write into `settings.json`

```json
{ "hooks": { "<Event>": [ { "matcher": "*", "hooks": [
      { "type": "http", "url": "http://127.0.0.1:<port>/hook", "async": true,
        "timeout": 5, "headers": { "Authorization": "Bearer <token>" } } ] } ] } }
```

`matcher` applies only to tool-scoped events (`PreToolUse`, `PostToolUse`,
`PermissionRequest`); omit it elsewhere.

## 4. Codex CLI

`~/.codex` **does not exist** on this machine and the `codex` binary is not
installed. The `CodexProvider` cannot be verified empirically, and `docs/09` M5
explicitly permits "skip and document if the surface isn't there".

**Decision:** ship the Codex provider as a *configuration* of the generic
provider (watch `~/.codex/sessions`, detect the binary) rather than as
unverifiable bespoke code. The generic provider covers it with zero speculative
parsing. Revisit when a machine with Codex installed is available.

### 4.1 ChatGPT.app — measured, and deliberately not supported

Installed here (`com.openai.chat` 1.2026.160), data in
`~/Library/Application Support/com.openai.chat`. Polled every second for 25
minutes on 2026-08-11, recording paths, sizes and mtimes only:

```
13:19–13:38  silence, 19 minutes, app running
13:38:31–37  burst: helper cache, models, system-hints, all 22 conversations,
             projects                                    ← foreground + sync
13:39:02     drafts-v2/NewThreadDraft.data          483
13:39:34     drafts-v2/NewThreadDraft.data          784
13:41:38–39  models, system-hints, gizmos/bootstrap        ← periodic refresh
13:42:23     drafts-v2/<conversation>.data          319
13:42:31 →   470 → 245 → 442 → 526 (last write 13:44:08)
```

**Not one write to `conversations-v3/` after the initial sync.** The only file
that moves turn by turn is the *draft*, and it moves in exactly the wrong
direction: it grows while the user types and stops the moment they send. A
watcher on this folder reports "working" while you compose and "idle" while the
model answers. It is also the folder holding unsent prompt text, which the
privacy promise in `docs/06` puts out of bounds even at the size-only level.

The 13:38 and 13:41 bursts are foreground sync and a periodic metadata refresh.
A folder watch would fire on both and hold the Mac awake for nothing — a false
hold, which `docs/01` ranks as worse than a missed one.

**Decision:** no ChatGPT preset. Independently of detectability, the plain chat
case does not want one: the work runs on OpenAI's servers and survives sleep,
so holding the Mac awake for it burns battery for nothing.

**Untested and still open:** Agent Mode / "Work with Apps", where ChatGPT drives
local applications and sleep *would* kill the run. `app_pairing_extensions` was
empty during this measurement, so that mode was certainly not active. Re-measure
with pairing configured before concluding anything about it. The `logo-chatgpt`
artwork ships already and needs no work if that case is confirmed.

## 5. Power assertions

`pmset -g assertions` output on this host confirms the reporting format the
README leans on, including the timeout line we depend on for the safety story:

```
pid 1079(nsurlsessiond): [0x00005100000188df] 00:00:01 PreventUserIdleSystemSleep
    named: "NSURLSessionTask 61631E3F-…"
    Timeout will fire in 10799 secs Action=TimeoutActionTurnOff
```

`PreventUserIdleSystemSleep` is the correct type name and appears both in the
system-wide summary and the per-process listing, so `pmset -g assertions | grep
-i belay` will show our assertion, its human-readable reason, and its remaining
timeout. Note the system already holds a `powerd` "Prevent sleep while display
is on" assertion whenever the display is awake — during manual QA the display
must be asleep (or that assertion accounted for) or every test looks like a pass.

## 6. Limitations of this pass

- `claude -p` headless runs report **"Not logged in"** on this machine, so a
  full agentic turn (with `PreToolUse`/`Stop`) could not be driven headlessly.
  `UserPromptSubmit` and `SessionEnd` were captured from a real run; the
  remaining events are mapped from the live reference and must be re-verified in
  the M3 manual QA pass against an interactive session. Tracked in
  `docs/QA-CHECKLIST.md`.
- ~~FSEvents on `~/.claude` is unverified.~~ **Resolved in M2: it works.** The
  throwaway probe that segfaulted here was simply buggy — it crashed against a
  scratch directory too. Built properly inside the provider and run against the
  real `~/.claude/projects`, the stream starts in 3 ms across 45 transcripts in
  19 project directories, emits nothing for the 44 stale ones, and tracks a live
  session. TCC does not interfere.
- Only macOS 26.4 was available. macOS 14/15 behaviour is untested; the code
  targets 14.0 and avoids anything newer without an availability guard.
- No sandbox-enabled build existed at discovery time; the MAS-scheme detection
  paths are exercised from M2 onward per risk **R5**.
