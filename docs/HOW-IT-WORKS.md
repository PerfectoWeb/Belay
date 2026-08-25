# How Belay works

Everything here used to live in `README.md`. It was moved out because a person
deciding whether to download an app should not have to read about state
machines first. But the detail is the reason to trust the app, so none of it
was cut.

For the design documents behind these decisions, see
[`02-ARCHITECTURE.md`](02-ARCHITECTURE.md), [`03-DETECTION.md`](03-DETECTION.md)
and [`DISCOVERY.md`](DISCOVERY.md).

---

## Detection

Two layers, both entirely local. Neither talks to a network.

### Transcript watcher, the default, with no setup

Claude Code appends each session's conversation to a JSONL file under
`~/.claude/projects/`. Belay watches those files with FSEvents and reads only
the bytes appended since it last looked: a per-session cursor keeps `(inode,
offset)`, so an 82 MB transcript costs the same to check as a fresh one.

The primary signal is simply **that a file grew**. That keeps working when the
record format changes, because it does not depend on the format at all.

On top of that, a classifier scans the new bytes backwards for the last
`assistant` or `user` record and reads its `stop_reason`. Metadata records are
ignored, because on a real machine the literal last line of a finished
transcript is metadata far more often than not.

No growth for 45 seconds infers idle — unless the turn is still waiting on an
answer, in which case a retrying model gets a longer, bounded grace instead of
a wrong "finished". Transcripts untouched for more than ten minutes at launch
are not followed at all, so starting Belay on a machine with dozens of old
projects does not resurrect them.

Codex gets the same treatment with less guessing: its session rollouts under
`~/.codex/sessions` carry explicit turn markers, so starts and finishes are
read, not inferred. Cline is plainer still: every session keeps a small state
file under `~/.cline/data/sessions` whose `status` field says running or
finished outright, and Cline's team mode writes one messages file per teammate
agent inside the session's folder — Belay shows those teammates in the panel
under their session, the way Claude Code subagents appear. No setup for any of
the three. Other tools — Gemini CLI, Copilot CLI, OpenCode, Aider, Cline
(VS Code), Pi — ship as one-click presets that watch the folder each tool
writes while it works.

### Hook bridge, optional and exact

All three built-in agents can tell Belay directly, through a listener on
`127.0.0.1`: prompt submitted, tool starting, turn finished, permission
needed. This gives sub-second detection and is what makes *"an agent is
waiting for you"* reliable rather than a guess. Claude Code POSTs from HTTP
hooks in `settings.json`; Codex runs command hooks from `hooks.json`, whose
approval Belay records in `config.toml` because Codex silently skips
unapproved hooks; Cline runs one small script per lifecycle event from
`~/.cline/hooks`. Each install shows a full preview first, is backed up, and
can be removed from the agent's tile.

The hooks are registered fire-and-forget, so no agent ever waits on Belay
for anything. There is no exit code Belay could return that would block your
agent, and no way for it to slow a turn down.

### One state machine

Signals from both layers feed a single decision. An exact signal outranks an
inferred one while it is fresh, so a trailing disk write cannot resurrect a turn
the hook has already reported as finished. A turn that ends while background
agents or shell jobs are still running keeps the hold until they finish, and a
question from the agent counts as "waiting for you" from the moment it is
asked.

## The safety rails

The failure mode that would make you uninstall this app is not *"it let my Mac
sleep"*. It is *"it kept my Mac awake for nine hours and I did not notice"*.
So the design assumes Belay itself will fail:

- **Every assertion is created with a 120-second timeout** and re-armed while
  work continues. Since 1.3.2 the hold is a pair: the sleep assertion and a
  network-client one beside it, so an awake Mac does not drop its SSH sessions
  or stall a streaming reply. If Belay crashes, hangs, is force-quit, or is killed by the
  OS, the Mac returns to normal sleep behaviour within two minutes. There is no
  such thing as a zombie caffeination, because there is nothing to clean up.
- **Every tracked session has a TTL.** A session that goes silent is presumed
  dead rather than presumed working.
- **A hard cap on continuous awake time** (default 4 hours).
- **A battery guard** (default: stop below 20% on battery).
- **Release on sleep, quit, `SIGTERM` and mode change.**

You never have to take any of that on trust:

```bash
pmset -g assertions | grep "pid $(pgrep -x Belay)("
```

The assertion, its plain-English reason, and its remaining timeout are all
there, printed by macOS rather than by Belay.

## Privacy

Belay reads only enough of a session file to know whether it is running:
**whether the file grew**, and a record's `type` and `stop_reason`. It never
reads your prompts, your model's responses, or your code.

The hook payload for `UserPromptSubmit` contains your entire prompt. Belay's
decoder **has no field for it**. It is never decoded, never logged, never
stored, and there is a test that proves it.

Two things reach the network, and neither carries anything about you: a daily
check for a newer version, which one switch turns off, and the download itself
after you press Update. Nothing is fetched or installed until you press it.

Full detail, including how to verify all of this yourself, is in
[`SECURITY.md`](SECURITY.md).

## Talking to Belay from anything

If your tool can run a shell command, it can tell Belay what it is doing. Port
and token come from `~/Library/Application Support/Belay/bridge.json`:

```bash
curl -s -X POST -H "Authorization: Bearer $TOKEN" \
  "http://127.0.0.1:$PORT/hook?provider=generic&session=my-tool&state=working"
```

`state` accepts:

| Meaning | Accepted values |
|---|---|
| Working | `working`, `busy`, `start` |
| Finished | `idle`, `stop`, `done` |
| Waiting for you | `waiting`, `blocked` |
| Session over | `ended`, `exit` |

An unrecognised state is **dropped rather than guessed**. Add `&workspace=name`
to control what the panel shows.

For tools that only write files, the folder watcher in **Settings ▸ Agents**
needs no code at all: point it at wherever the tool writes while it is working.

## Requirements

macOS 14 or later. Nothing else: no Apple Developer account, no agent account,
no network.

macOS 14, 15 and 26 have all been run for real on Apple silicon;
[`QA-CHECKLIST.md`](QA-CHECKLIST.md) is the honest list of what has and has not
been verified.
