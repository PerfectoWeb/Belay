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

No growth for 45 seconds infers idle – unless the turn is still waiting on an
answer, in which case a retrying model gets a longer, bounded grace instead of
a wrong "finished". Transcripts untouched for more than ten minutes at launch
are not followed at all, so starting Belay on a machine with dozens of old
projects does not resurrect them.

Codex gets the same treatment with less guessing: its session rollouts under
`~/.codex/sessions` carry explicit turn markers, so starts and finishes are
read, not inferred. Cline is plainer still: every session keeps a small state
file under `~/.cline/data/sessions` whose `status` field says running or
finished outright, and Cline's team mode writes one messages file per teammate
agent inside the session's folder – Belay shows those teammates in the panel
under their session, the way Claude Code subagents appear. Copilot CLI keeps
one event log per session under `~/.copilot/session-state`, with explicit turn
markers and a shutdown record, so its starts and finishes are read exactly
without any hooks. No setup for any of the four. Other tools – Gemini CLI,
OpenCode, Aider, Cline (VS Code), Pi – ship as one-click presets that watch
the folder each tool writes while it works.

An agent that lives somewhere else – `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, a
second profile – is added from its tile: open **Watched Folders** in the
agent's menu and pick the folder. Belay watches every added folder alongside
the default home, one watcher per folder.

### Hook bridge, optional and exact

Claude Code, Codex and Cline can tell Belay directly, through a listener on
`127.0.0.1`: prompt submitted, tool starting, turn finished, permission
needed. (Copilot's own log already carries exact markers, so it has nothing
to install.) This gives sub-second detection and is what makes *"an agent is
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

## Modules

Extras that have nothing to do with sleep, in **Settings ▸ Modules**, each one
off until you install it. A module is part of the app: installing one downloads
nothing, switching it off keeps its settings, removing it forgets them. The
list is open to pull requests: [MODULES.md](MODULES.md) is the guide to writing
one.

**Screenshot Cleaner** moves screenshots to the Trash once they pass the age you
choose. It knows a screenshot by the mark macOS writes on the file
(`kMDItemIsScreenCapture`), never by the name, so renaming one does not hide it
and naming a file "Screenshot" does not endanger it. It looks every five
minutes, in the folder's own files only, and leaves alone anything you tagged or
edited unless you switch that off. Screenshots that were there before you
switched it on get the full age from that moment. The App Store build asks you
to choose the folder; the direct build starts with the one macOS saves to.

A Desktop kept in iCloud Drive is a special case. There macOS passes the
ordinary "move to Trash" request to its file provider, which refuses an app
that was allowed the Desktop by the usual question. The direct build then moves
the file into your Trash itself, on the same disk and never over a file already
there. The one thing such a file lacks is Finder's Put Back; dragging it out of
the Trash works as always.

**Warm Microphone** holds the microphone open. macOS powers down a microphone
nobody is reading, and the next app to open it waits for it to start, which is
where the first word of a dictation goes. The module reads the microphone and
throws the sound away as it arrives: no recording, no level meter, no buffer
kept. It follows the input macOS is set to use, reopens three seconds after a
headset is plugged in or the input is switched, and comes back after sleep.
One permission covers every microphone: macOS grants it to Belay, not to a
device, and only the input in use is held. One cost cannot be engineered away:
macOS shows the orange microphone dot for as long as a microphone is held.

A Bluetooth microphone is the exception. Holding one keeps the headphones in
call mode, which lowers the quality of what you listen to, so with "Leave
Bluetooth headphones alone" on, as it is by default, the module lets go while
AirPods or another Bluetooth microphone are the input and picks up the next
input when they are gone. "Pause on battery power" lets the microphone go while
the Mac is unplugged. An app that was told to use a microphone other than the
one macOS is set to gains nothing from the module.

Carrying the module changes one thing for everybody, installed or not. macOS
asks for the microphone when any sound starts on an output device that also
records, such as a USB audio interface or a headset, if the app is one that may
be asked. So until the microphone question has been answered in the module,
Belay plays no sounds on such a device: a click in the panel is never what
raises that question. On speakers and displays nothing changes.

**Auto Allow** presses "Allow once" in the Claude desktop app and in Codex,
the agent inside the ChatGPT desktop app. Both ask before an action on a site
they have no site-level permission for, and for a site that exists only on
your Mac there is no way to grant one, so an agent testing `myshop.local`
stops at every click. The module looks at each app's window every two seconds
through the Accessibility interface, finds the request card, and reads what
it asks for. With the default setting it presses the button only when the
card is a request for access to a site, the site is local (`localhost`, a name
ending in `.local`, `.localhost`, `.test`, `.internal`, `.lan` or
`.home.arpa`, or a private address), and no other site is named on the card.
A command to run, a file to change, a site on the internet: all of those wait
for you. "Everything the agent asks" approves them too, and says so in orange
when you choose it. Either way the module switches itself off after the time
you set, a restart does not give it more time, and the card lists the latest
approvals with the time and the site.

The two apps say what they ask differently. Claude puts the site into a
record beside the question. Codex writes the question in the agent's own
words and marks the site as a link in it, so in Codex only that link counts: a
command that happens to mention `localhost` is a command, and waits for you.
Codex also ignores the click the Accessibility interface sends to a button;
there the module gives the button the focus and sends the Return key to the
Codex process, and only while the button says it has the focus.

A request card exists only in the session the window is showing, and agents
mostly work in the ones behind it. With "Answer in sessions behind the window"
on, the module reads the list of sessions beside the window, and when one says
it is awaiting input (Claude) or awaiting approval (Codex) it opens that
session, answers what the rules cover, and brings back the session you had
open. It does that only when the shown session has nothing to answer, only
once the keyboard and the pointer have been still for five seconds, in
whatever app you are working, and one session at a time. Bringing a session
into the window can pull the app to the front, which is why it waits for a
pause and never cuts into a sentence. When a visit has pulled the agent's app
to the front, the app that was in front before is brought back, unless the
keyboard or the pointer has moved in the meantime. A session that turned out
to wait for something the rules do not cover is not opened again until it has
moved on. Two sessions with the same name are left alone, since they cannot be
told apart, and so is a list where the session on show has a namesake, since
the way back would be in doubt.

A page shown inside either window, such as a site in the agent's own browser,
is passed over: whatever it draws is not a request card.

A module that works for an agent follows that agent's switch in **Settings ▸
Agents**: with Claude Code or Codex switched off there, Auto Allow reads
nothing and presses nothing in that app, and its card says so.

Auto Allow is in the direct build only. In Claude it works with the interface
set to English; in Codex it knows the button and the mark in every language
the app speaks. It recognises the card and the list by what each app calls
them: if an update changes that, the module finds nothing and presses nothing
until Belay is updated.

**Nudge** says it out loud when an agent finishes, waits for you or goes quiet.
It reads the same picture of your sessions the panel shows, which are working,
which wait and which are gone, and nothing else: no transcript, no prompt.
Three short sounds, one struck note each, tell the events apart without
looking: a run that ended, a session that waits for you (a touch higher) and a
session that went quiet (the lowest). Each has its own checkbox, and all of
them follow the macOS setting for interface sound effects.

A session that keeps waiting gets a reminder banner, "Still waiting for you",
after the time you choose (2, 5, 10 or 15 minutes, or never), again at the
same interval, and at most as many times as you choose (1, 3, 5 or 10). The
first banner, "An agent is waiting for you", is the one from Notifications and
the module does not repeat it; the count starts over when the session resumes.
"A run finishes, naming its workspace" posts one banner per session, with the
workspace and how long the run took, for runs at least as long as "Ignore runs
shorter than" (10 seconds, 30 seconds, 1 minute or 5 minutes). Time spent
waiting for you is not counted as time worked. This banner is per session,
unlike "Your agent finished" in Notifications, which is per stretch of holding,
so with both on you may get both. A subagent does not ring on its own: a run
ending or a silence is about the session you started, while a subagent that
waits for you does count, because the whole run stands still on it.

Clicking a Nudge banner brings forward the app the session lives in. For a
Claude Code session the session file in `~/.claude/sessions` says whether it
runs inside the Claude desktop app; if so, that app. Otherwise the application
that owns the session's process, the terminal or the editor, found by walking
from the process up through its parents: only the process and parent-process
numbers are read, never another process's arguments. For Codex it is the
ChatGPT app, when it is running. When none of these can be found, the banner
raises nothing.

The first switch-on asks macOS for permission to send notifications. If that
is refused the card says so in red and offers the button to System Settings;
the sounds carry on.

**Orphan Watch** finds what an agent started and left running after its
session ended: a dev server, an MCP server, a headless browser nobody closed.
Once a minute it reads the process table, the same table Belay reads to tell
whether an agent is alive, and takes as agents every process named `claude` or
`codex` and every process in Claude Code's session registry that is still the
process that wrote its file. It remembers what runs below each of them, up to
eight levels down, by number and start time. When an agent is gone, or its
number belongs to another process now, whatever it started and still runs is
listed as left behind, with its name, its number, its age and the agent it
came from. Only what was seen below a live agent is listed, so a process that
was orphaned before Belay looked is not claimed, and nothing is written to disk
except the rules and the names you ignore. A number handed out again is never
taken for the old process: the start time has to match too.

With "List processes running hot" on, as it is by default, an agent process or
one of its descendants that averaged more than the share of a core you chose
(30, 50 or 80 percent) over the time you chose (5, 10 or 30 minutes) is listed
as running hot, provided no session of that agent was working in Belay's own
view at any point in that time. The CPU time comes from the system for the
remembered processes only.

Names are the short command name the system keeps (sixteen characters), never a
path and never arguments: Belay does not read another process's command line.
"Ignore" on a row leaves that name out of the list and the counts. A banner,
"Left behind by an agent", says so once when something new appears, in one
banner per look, and a click on it opens Settings ▸ Modules.

In the direct build, "End" on a row and "End All" ask first, then send each
process the polite request to quit (SIGTERM), look again two seconds later and
say how many are still running. Nothing stronger is ever sent and nothing is
ended without a press. "End All" covers what was left behind, never a process
listed as running hot, which may be an agent that is working. The App Store
build lists and ends nothing, since its sandbox lets no signal out; the card
points to Activity Monitor. Orphan Watch follows the agent's switch in
**Settings ▸ Agents** like the other modules that work for an agent.

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
