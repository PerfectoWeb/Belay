# Belay

> Keeps your Mac awake exactly as long as your AI coding agent is working, and
> not a minute longer.

Belay is a macOS menu bar utility. It watches your local coding agent, holds a
system-sleep assertion only while the agent is genuinely working, and lets macOS
go back to your normal sleep schedule the moment everything goes quiet. Your
System Settings are never touched.

No API key. No account. The only thing that ever leaves your Mac is a daily
check for a newer version, which carries nothing about you and which one switch
turns off.

---

## The problem

You start a long Claude Code task and walk away. Ten minutes later your Mac
sleeps and the run dies. So you set sleep to "Never", forget to change it back,
and your laptop cooks itself for a week.

The cost of getting this wrong is lopsided: sleeping too early kills a
long-running job silently and wastes both tokens and an evening, while staying
awake sixty seconds too long costs nothing. Belay is tuned accordingly.

## How it works

Two layers, both entirely local.

**Transcript watcher** (default, zero setup). Claude Code appends each session's
conversation to a JSONL file under `~/.claude/projects/`. Belay watches those
files with FSEvents and reads only the bytes appended since it last looked. The
primary signal is simply that a file grew, which keeps working even when the
record format changes, because it does not depend on the format at all.

**Hook bridge** (optional, exact). Claude Code can POST lifecycle events, prompt
submitted, tool starting, turn finished, permission needed, to a listener
Belay runs on `127.0.0.1`. This gives sub-second detection and is what makes
"an agent is waiting for you" reliable. The hooks are registered as
`"async": true`, which means Claude Code never waits on Belay for anything.

Signals from both layers feed one state machine that decides whether to hold.
An exact signal outranks an inferred one while it is fresh, so a trailing disk
write cannot resurrect a turn the hook already said was finished.

## Safety

The failure mode that would make you hate this app is not "it let my Mac sleep".
It is "it kept my Mac awake for nine hours and I did not notice". So:

- Every assertion is created with a **120-second timeout** and re-armed while
  work continues. If Belay crashes, hangs, is force-quit, or is killed by the OS,
  your Mac returns to normal sleep behaviour within two minutes. There is no such
  thing as a zombie caffeination.
- Every tracked session has a TTL. A session that goes silent is presumed dead.
- A hard cap on continuous awake time (default 4 hours), a battery guard
  (default: stop below 20% on battery), and release on sleep, quit, `SIGTERM`
  and mode change.

Check any of it yourself:

```bash
pmset -g assertions | grep "pid $(pgrep -x Belay)("
```

You will see the assertion, a plain-English reason, and its remaining timeout.

## Requirements

macOS 14 or later. Nothing else: no Apple Developer account, no agent account,
no network. Only macOS 26 on Apple silicon has been tested so far. Claude Code
is detected with no setup;
anything else is configured in Settings, Providers. Building it yourself needs
Xcode 16 or later, plus `xcodegen`, `swiftlint` and `swift-format` from Homebrew.

## Install

**[Download Belay](https://github.com/PerfectoWeb/Belay/releases/latest/download/Belay.dmg)**
— macOS 14 or later, Apple silicon and Intel. Open the disk image and drag Belay
to Applications.

The app and the disk image are both signed with a Developer ID and notarized by
Apple, and both carry a stapled ticket, so the first launch works with no
network and without right-click-Open.

Or build it yourself, which needs no Apple Developer account:

```bash
git clone https://github.com/perfectoweb/belay.git && cd belay
scripts/build-local.sh
open build/Belay.app
```

That one is ad-hoc signed and will not open on anyone else's Mac without a
right-click.

On first launch you get one screen explaining what Belay reads. Then it lives in
the menu bar: left-click for the panel, right-click for a compact menu.

## Modes

| Mode | What it does |
|---|---|
| **Auto** (default) | Awake if and only if an agent is working |
| **Always on** | A better `caffeinate`, with the same safety rails |
| **Off** | Belay holds nothing |

## Privacy

Belay reads only enough of your agent's session files to know whether it is
running: whether a file grew, and a record's `type` and `stop_reason`. It never
reads your prompts, your model's responses, or your code.

The hook payload for `UserPromptSubmit` contains your entire prompt. Belay's
decoder has no field for it. It is never decoded, never logged, never stored,
and there is a test that proves it.

Full detail, including how to verify all of this yourself, is in
[`SECURITY.md`](SECURITY.md).

## Languages

English, Russian, German, Spanish, French and Italian. Belay follows your Mac's
language and falls back to English when it does not ship yours; Settings ▸
General has a picker, and changing it reopens the app, because the menu bar menu
and the alerts are AppKit and will not switch language under a running process.

None of the translations have had a native review yet. The copy in this app is
voicier than most interface text, which is exactly where a translation slips, so
corrections are genuinely welcome, and each one is a one-line change in
[`Resources/Localizable.xcstrings`](Resources/Localizable.xcstrings).

## FAQ

**Why not just use `caffeinate`?**
Because you have to remember to stop it. `caffeinate -i` holds until you kill it,
so a forgotten terminal tab keeps the Mac awake all week, and if it dies with the
shell your run dies with it. Belay starts and stops on its own, its assertion
expires by itself if the app is not there to refresh it, and it will not hold
past four hours or below 20% battery no matter what your agent is doing. Always
on mode is `caffeinate` with those rails, if that is all you want.

**Does it work with a closed lid?**
No, and nothing can make it. An idle-sleep assertion does not keep a MacBook
awake with the lid shut; macOS enters clamshell sleep unless the machine is on AC
power with an external display attached. Belay will not pretend otherwise.

**My screen still turns off.**
That is intentional and saves real power. Belay prevents *system* sleep; the
machine underneath keeps working. There is a setting to keep the display awake
too, off by default.

**Why not use the Anthropic API to ask if my agent is busy?**
There is no such endpoint. The API has no knowledge of a local Claude Code
process, so asking it would cost money to learn nothing. Any design that needs
you to paste an API key is solving a different problem.

**Why not watch CPU usage?**
It fails in both directions. An agent waiting ninety seconds on a network
response uses no CPU but is very much working, and a language server in the same
project can peg a core while nothing is happening.

**What about Codex, Aider, Gemini CLI, Cline, DeepSeek?**
Claude Code is first-class. Everything else is covered by the generic provider,
configured in Settings > Providers: watch a folder, watch a process, or send
Belay a webhook. Aider, Gemini CLI, Cline and Codex CLI ship as presets, which
are pre-filled configurations, not code. On DeepSeek specifically: there is no
first-party DeepSeek CLI to hook into; it is consumed through other tools, and
those tools are what Belay watches.

**Integrating a tool Belay has never heard of**
If your tool can run a shell command, it can talk to Belay in one line. Port and
token come from `~/Library/Application Support/Belay/bridge.json`:

```bash
curl -s -X POST -H "Authorization: Bearer $TOKEN" \
  "http://127.0.0.1:$PORT/hook?provider=generic&session=my-tool&state=working"
```

`state` accepts `working` / `busy` / `start`, `idle` / `stop` / `done`,
`waiting` / `blocked`, and `ended` / `exit`. An unrecognised state is dropped
rather than guessed. Add `&workspace=name` to control what the panel shows.

**Will the hooks slow Claude Code down?**
They cannot. They are registered `"async": true`, so Claude Code does not wait
for a response, and there is no exit code that could block anything.

**It stopped keeping my Mac awake.**
Check the panel. It always says why in plain language: battery guard, maximum
awake time, or simply that nothing is running.

## Contributing

Start with [`CONTRIBUTING.md`](CONTRIBUTING.md). The two contributions wanted
most are a fix to one of the six translations, none of which have had a native
review, and a preset for an agent Belay does not know about yet; both are data
rather than code, and neither needs you to learn the codebase.

## Development

```bash
scripts/test.sh          # build, tests, both linters, everything CI runs
scripts/build-local.sh   # ad-hoc signed .app in build/
scripts/perf-soak.sh     # measure against the performance budgets
```

Tests live in two places on purpose: the module suites run under `swift test`,
and `xcodebuild test` runs the app-target tests, because an XcodeGen scheme
cannot reference a local SwiftPM package's test targets.

`Belay.xcodeproj` is generated by XcodeGen from `project.yml` and must never be
hand-edited.

Architecture, the detection design, and the empirical findings that shaped both
are in [`docs/`](docs/). Start with
[`docs/02-ARCHITECTURE.md`](docs/02-ARCHITECTURE.md) and
[`docs/DISCOVERY.md`](docs/DISCOVERY.md). Decisions and where the implementation
deliberately diverged from the original specs are in
[`PROJECT_STATE.md`](PROJECT_STATE.md).

## Status

v1.0, built and verified on macOS 26.4. macOS 14 and 15 are supported targets but
have not yet been exercised on real machines. See
[`docs/QA-CHECKLIST.md`](docs/QA-CHECKLIST.md) for exactly what has and has not
been verified, including the items still outstanding.

## License

MIT. See [`LICENSE`](LICENSE).

### Trademarks

The Active Sessions list shows each tool's own logo, so you can tell at a glance
which agent is working. All product names, logos and trademarks are the property
of their respective owners; they are used here only to identify those products
and imply no affiliation or endorsement. See [`NOTICE.md`](NOTICE.md).
