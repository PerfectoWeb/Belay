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

No growth for 45 seconds infers idle. Transcripts untouched for more than ten
minutes at launch are not followed at all, so starting Belay on a machine with
dozens of old projects does not resurrect them.

### Hook bridge, optional and exact

Claude Code can POST lifecycle events to a listener Belay runs on `127.0.0.1`:
prompt submitted, tool starting, turn finished, permission needed. This gives
sub-second detection and is what makes *"an agent is waiting for you"* reliable
rather than a guess.

The hooks are registered as `"async": true`, so Claude Code never waits on Belay
for anything. There is no exit code Belay could return that would block your
agent, and no way for it to slow a turn down.

### One state machine

Signals from both layers feed a single decision. An exact signal outranks an
inferred one while it is fresh, so a trailing disk write cannot resurrect a turn
the hook has already reported as finished.

## The safety rails

The failure mode that would make you uninstall this app is not *"it let my Mac
sleep"*. It is *"it kept my Mac awake for nine hours and I did not notice"*.
So the design assumes Belay itself will fail:

- **Every assertion is created with a 120-second timeout** and re-armed while
  work continues. If Belay crashes, hangs, is force-quit, or is killed by the
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
[`../SECURITY.md`](../SECURITY.md).

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

For tools that only write files, the folder watcher in **Settings ▸ Providers**
needs no code at all: point it at wherever the tool writes while it is working.

## Requirements

macOS 14 or later. Nothing else: no Apple Developer account, no agent account,
no network.

macOS 26 and macOS 15 have been exercised on Apple silicon, 14 has not;
[`QA-CHECKLIST.md`](QA-CHECKLIST.md) is the honest list of what has and has not
been verified.
