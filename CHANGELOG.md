# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.3] - Unreleased

### Fixed

- Touched old transcripts stop appearing as phantom rows. Restarting the
  Claude desktop app rewrites several transcripts at once, and each used to
  show up as an idle session that never did anything — the same suppression
  Codex already had now covers Claude Code: a session whose first classified
  state is idle is followed silently until a real turn announces it.
- Sessions stop flapping after a turn ends. The bookkeeping both CLIs write
  once a turn closes — titles, summaries, token counts — used to flip a quiet
  session back to Working every burst. Unclassifiable bytes now prolong a
  running turn (that rule protects against format changes) but never restart
  a quiet one: a real turn opens with a record the classifier can read.
- The panel's elapsed column tells the truth per state: an idle session now
  shows how long it has been quiet, not its age — a session that worked three
  minutes ago no longer reads "Idle · 24m".
- A finished turn can no longer ride the retry grace: the idle sweep re-reads
  the transcript before judging silence, so closing records that landed just
  after the last delta are seen instead of aging toward a false "went quiet".
- Opening the Codex app no longer floods the panel. Its housekeeping touches
  dozens of old rollouts at once, and each used to appear as an idle session
  that never did anything. A session whose first classified state is idle is
  now followed silently; the first real turn still announces it.

### Changed

- A crashed Codex ends its sessions within seconds: when no `codex` process
  remains, a working session is a crash, not a retry, and it no longer earns
  the fifteen-minute grace.
- The lid hold's hard cap counts on the monotonic clock, so dragging the date
  backwards can no longer extend a privileged flag.
- The lid helper records what `disablesleep` was before it raises the flag —
  sentinel first, flag second, crash-safe in that order — and restores that
  value instead of assuming zero. A Mac whose owner runs `disablesleep 1`
  deliberately keeps their setting, including across reboots: startup now
  restores only when the sentinel says the flag is Belay's, lowering it never
  touches a flag that was never ours, and the first start after this update
  clears any pre-sentinel leftover exactly once.

## [1.3.2] - 2026-08-20

### Added

- Codex graduates to a first-class provider. Its session rollouts persist
  explicit turn markers, so Belay now reads exact turn edges — including the
  retry grace and "went quiet" semantics Claude Code already has — instead of
  guessing from folder activity. The old Codex CLI preset retires, and an
  existing preset tile migrates away on first launch so nothing reports twice.
- Background work survives the end of a turn. A Claude Code `Stop` that
  reports live background tasks no longer releases the hold: background
  agents and shell jobs keep the Mac awake until they are done or the
  session ages out. Only the count of tasks is read, never their content.
- A question is not work. `AskUserQuestion` and `ExitPlanMode` starting now
  read as "waiting for you" from the moment the tool fires, not from a later
  notification.
- Every hold now carries a network-client assertion beside the sleep one, so
  a kept-awake Mac keeps its SSH sessions and streaming API calls alive too.
- Presets for GitHub Copilot CLI and OpenCode. Copilot CLI streams
  `session-state/<uuid>/events.jsonl` during a turn — verified on a real
  install — and OpenCode writes its database WAL at every tool call, so both
  give the folder watcher a live signal. Both tools also ship hook systems,
  which leaves the road to exact detection open.

### Changed

- The preset menu leads with the big four CLIs: Gemini, Codex, Copilot,
  OpenCode, then Aider, Cline and Pi.
- The App Store build's About pane rearranges its icons: the star now sits on
  "Rate Belay", where a star actually pays Belay back, and "Star on GitHub"
  wears the GitHub mark. The direct build keeps the star on GitHub.

### Fixed

- A preset whose folder does not exist yet is described honestly: "No
  ~/.codex/sessions yet. It appears once the tool has run." The badge used to
  ask for a read permission that would have fixed nothing, and named the
  folder by its bare last component.

## [1.3.1] - 2026-08-19

### Added

- The statistics chart answers the cursor. Hover a day and its bar lifts while
  the others step back, the four figures switch to that day's numbers with a
  digit-roll, and the "Last 14 days" label becomes the date. Empty days do not
  react, and Reduce Motion turns every part of it into a plain redraw.
- A Pi preset in Settings, asked for in issue #3: one click watches
  `~/.pi/agent/sessions`.
- The lid guards say so out loud (direct builds): when the heat release or the
  time cap ends a closed-lid hold, a notification names which guard let go.
- A debug-only Release Flow window replaces three loose workbench menu items:
  replayable release screens, Sparkle and App Store notes editable in place,
  and a per-version release checklist. Compiled out of release builds.

### Changed

- A turn that waits out its whole grace without an answer now ends as "went
  quiet", so the notification reports a stall rather than a finish.
- Belay launched while an agent is mid-retry adopts the fresh transcript at
  once instead of waiting for the next write.
- The lid helper's caption in Settings refreshes when the app becomes active,
  so approving it in System Settings shows up without reopening the pane.

### Fixed

- Failed update checks now log their reason to Diagnostics instead of
  vanishing silently.
- `release.sh` survives Xcode 26.6, whose `-exportArchive` broke: the app is
  laid out from the archive and re-signed inside out, with fail-closed checks
  at every step.

## [1.3.0] - 2026-08-19

### Added

- The display dims at night. While Belay keeps the screen awake and you step
  away inside a set window, it fades to a chosen level and comes back the
  moment you return. Off by default, works through the display's gamma table,
  and a crashed Belay cannot leave the screen dark: macOS restores gamma when
  the process that set it dies.
- Keep working with the lid closed. Direct builds only, off by default. A
  system helper, approved once in Login Items, holds the kernel's own sleep
  switch while an agent works, and always lets go by itself: when the work
  ends, when Belay stops asking, at a hard time cap, or if the Mac runs hot
  with the lid shut. Proven both ways on battery: flag up, the lid shut and
  music kept playing; flag off, asleep in seventy seconds.
- A retrying agent now keeps the hold. When the model is overloaded, the CLI
  writes nothing for minutes and Belay used to read that as idle — at exactly
  the moment the run most needed the Mac awake. A turn still waiting on an
  answer now gets a longer, bounded grace, and the CLI's own error records no
  longer read as a finished turn.
- Sounds: the welcome scene got a spell, a score and typing under the little
  screen; the What's New window arrives like a TV switching on, with a chime.
- Diagnostics now log what Belay did — holds, sessions, dimming, the lid —
  not only crashes. Same local file, still nothing leaves the Mac.

### Changed

- What's New shows the version just installed and nothing else.
- The night window fields centre their digits and step by quarter hours.
- Update Now is the system button in green, not a capsule.
- Verified on macOS 14: the full 1.3.0 build was exercised on a real install,
  which closes the last line of the 14/15/26 support claim.

### Fixed

- Closing the welcome window mid-scene now stops its sounds and its script.
- No more false "main thread stalled" report after a system sleep.

## [1.2.1] - 2026-08-18

### Added

- The menu bar mark says when an update is waiting, and only while nothing is
  running. Direct builds only.
- One notification per new version, never a second for the same one. Clicking it
  opens the window with the install button. Direct builds only.
- Belay says when an agent goes quiet: a session that stopped sending anything
  and never said it had finished. Subagents count, so a parent waiting while its
  children work is not silence.
- Local crash reports, off by default. A switch in General writes crashes,
  freezes and errors to a file on this Mac, with a button to show it and a link
  to open an issue. Nothing is sent anywhere.

### Changed

- A run that died is no longer also announced as finished. The two fired
  together and only one of them was true.
- What's New shows the version being announced and nothing else. The history
  lives in this file.

### Removed

- "Skip This Version" and everything behind it. The mark is quiet enough to
  ignore without a control for ignoring it.

## [1.2.0] - 2026-08-17

Everything the direct build gained since 1.1.0.

### Added

**A "What's New" screen.** Shown once, on the first launch after an update, in
the same window as the welcome screen: same width, same margins, same lit panel,
same single button. Three to five things get an icon and a sentence; everything
else real gets one line under "Also", which is what keeps a release with ten
changes in it from becoming a wall of icons.

Items are channel-aware. `Update Now` and Homebrew are direct-build facts, and
the App Store build is shown neither, for the same reason Precise Detection came
out of the store listing: a screen must not promise what its build cannot do.

The rule that decides who sees it is `WhatsNewDecision`, which is pure and has a
test per branch. The case that needed the most care is the quiet one: everybody
already running Belay has no record of a last-seen version, and reading that as
"new install" would announce this release to people who have been running it for
months. They are recorded silently instead and told nothing.

The window has no scroll view. A `ScrollView` has no height of its own to
report, so a window sized from its content clips the last item mid-sentence,
which is what the first two attempts did. The window grows with the list, and
the number of items that can reach it is capped at six, which bounds the height
where it can be reasoned about rather than hoped about.

**Belay installs its own updates.** The update row is one button: `Check Now`
when there is nothing to install, and a green `Update Now` when there is.
Pressing it downloads the new version, checks it against the signing key
compiled into the running app, replaces the app and offers to relaunch. Sparkle
does that part; nothing here reimplements it.

The right-click menu carries the same job: **Check for Updates** until there is
one, then **Update Now (v1.3.0)** naming the version, so the row says what
pressing it will get you.

Updating in place begins with this version and cannot reach back. Sparkle
refuses an update whose app carries no signing key when the running one does,
correctly, and 1.0.0 and 1.1.0 shipped before the key existed. Anyone on those
updates by hand or through Homebrew once, and never again after that.

**Folders are remembered.** A folder picked for a generic target is kept as a
security-scoped bookmark, one per folder, so the sandboxed build can read it at
all and can still read it after a relaunch.

**Homebrew.** `brew install --cask belay`.

### Changed

**The paused mark is part of the icon rather than a badge on it.** Two bars are
cut out of the big star, with no circle and no border. It was a badge in the
corner before, and a strike through the mark before that: the strike said
*forbidden*, which is wrong, and at 17 points a bordered circle reads as a
notification dot.

**"Skip for now" is drawn, not borrowed.** A bordered system button looked like
a different app's control on macOS 15, beside a button that is drawn. It now
shares the primary button's measurements exactly.

**The licence.** MIT until 1.1.0, and the Belay Source-Available Licence from
here: forking and using are free, selling is not, and attribution is required.

### Fixed

**Quitting did not release the hold.** `shutdown release timed out` appeared in
the log on every quit: a `@MainActor` type blocked the main thread on a
semaphore while waiting for work that needed the main actor to finish. The hold
outlived the app until its own two-minute timeout reaped it. Found on macOS 15
and fixed there.

**The welcome window opened off-centre on macOS 15.** Its size was read before
AppKit had laid it out, so the centring arithmetic ran against a size of zero
and put the window's corner in the middle of the screen. It is sized from the
hosting controller's fitting size now, which does not depend on when a layout
pass happens.

**The disk image showed its own hidden files** when Finder was set to show them.

## [1.1.0] - 2026-08-14

A new welcome screen, and two fixes. Nothing about detection, power or the panel
changed: this release is what somebody sees in the first thirty seconds and the
two bugs found underneath it.

### Added

**A welcome screen that shows what the app does instead of describing it.** The
greeting is handwritten and draws itself, traced from the artwork as thirty-one
curve segments and stroked by trimming a path. No animation runtime, no asset
loaded at launch, and one number under `withAnimation`. It plays once, on
opening, and never comes back.

What follows it is a twelve-second loop: a MacBook with an agent writing into
it, Belay's mark beside it as the sun of a circular orbit, four agents going
round and finishing one at a time, the mark blinking and going grey, and the
screen falling dark under a moon with three letters rising off it. The machine
is Apple's own product bezel, whose display is cut out of the artwork, so our
screen sits behind it; the two PNGs come to fifteen kilobytes.

**Sound under the scene, and only there.** An agent finishing is a bubble; the
Mac letting go and coming back are the same two notes read in either direction.
All three are synthesised by `scripts/make-sounds.swift` like every other sound
in the app, and all three are gated by the system's interface-sounds preference
and then by Belay's own switch.

### Fixed

**The scene's sound drifted away from the picture.** It was scheduled as a chain
of relative sleeps, wait the gap, play, wait the next gap, and `Task.sleep`
guarantees a floor rather than a deadline. On the main actor, which is redrawing
the scene thirty times a second, every wait wakes a little late and the error
accumulates: about three quarters of a second per pass, so by the fifth pass the
sleeping note landed on a lit screen. Every wait is now measured to its due
moment on the same clock the picture is drawn from, and a cue more than 0.35 s
late is dropped rather than played against the wrong frame.

**The folder picker could attach its sheet to an invisible window.**
`GenericTargetsSection.hostWindow` matched the settings window by identifier and
took the first hit, but a closed settings window lingers in `NSApp.windows`, so
a session that had opened settings twice had two candidates and picked between
them by luck. Losing looked, from the outside, like the picker refusing to open.
It now requires the window to be visible. This was `docs/BLOCKERS.md` B9, the
intermittent CI failure that had never been identified.

**The update check retried hourly whenever it failed.** The timestamp that
paces it to once a day was written only after a successful fetch, so an offline
Mac left nothing behind and every hourly tick read the check as still due, up
to twenty four attempts in a day the app, the privacy policy and the release
notes all describe as one. The attempt is what gets recorded now, because the
attempt is what was promised.

**Three mode names were clipped in translation.** All three sit side by side in
one 330pt panel, and Spanish ran four points over the tab it had to fit in;
Italian and French cleared it by less than two. Shortened in Spanish, Italian,
French and German, and a test now measures every language against the metrics
the picker lays out with.

## [1.0.0] - 2026-08-13

First release of Belay, a macOS menu bar app that holds the Mac awake only while
a local AI coding agent is actually working, and lets it sleep normally the rest
of the time. Detection is entirely local: no API key, no account, no telemetry.

Built and verified on macOS 26.4; the deployment target is macOS 14.0. See
`docs/QA-CHECKLIST.md` for exactly which checks have been run on a real machine
and which have not.

### Added

**Menu bar app.** `LSUIElement`, so there is no Dock icon and no window on
launch. An `NSStatusItem` with a template glyph conveys state by shape and never
by animation; left-click opens a SwiftUI panel hosted in an `NSPopover`,
right-click opens a compact menu with the mode picker and Quit. Three modes:
Auto (hold if and only if an agent is working), Always on, and Off.

**Tier A, transcript detection for Claude Code, with no configuration.**
FSEvents watches `~/.claude/projects`; a per-session cursor keeps `(inode,
offset)` and reads only the bytes appended since the last look, so an 82 MB
transcript costs the same as a fresh one. The primary signal is that the file
grew, which does not depend on the record format. On top of that, a classifier
scans the delta backwards for the last `assistant` or `user` record and reads its
`stop_reason`; metadata records are ignored, because on a real machine the
literal last line of a finished transcript is metadata far more often than not.
No growth for 45 s infers idle. Transcripts untouched for more than 10 minutes at
launch are not followed, so starting Belay on a machine with dozens of old
sessions does not pin the Mac awake.

**Tier C, process presence.** Every 15 s, `~/.claude/sessions/<pid>.json` is
read and each pid checked with `kill(pid, 0)`. A session whose process is gone
ends immediately instead of waiting out its TTL. Only sessions Belay is already
following are considered, and process presence never produces `.working`.

**A generic provider for everything else.** One actor hosting any number of
configured targets, each of which can watch a folder, require a named process to
be alive, or accept a routed local webhook. Any one of the three is enough.
Presets are data rather than code: Aider, Gemini CLI, Cline and Codex CLI ship as
pre-filled configurations, and adding another is one array element. Every signal
it produces is `.inferred`, webhook reports included, so an unverified local
caller can never override an exact idle from the hook bridge.

**Tier B, the hook bridge (opt-in, exact).** An `NWListener` bound to
`127.0.0.1` on an ephemeral port receives Claude Code's HTTP hooks. The port and
a 256-bit bearer token live in `~/Library/Application Support/Belay/bridge.json`,
created `0600` inside a `0700` directory; a request without the token is answered
401 and its body is never parsed. Fourteen hook events are registered, all with
`"async": true`, so Claude Code never waits on Belay and there is no exit code
that could disrupt a turn.

**Consent-gated hook installation.** Belay writes to `~/.claude/settings.json`
only from a button, and shows the exact JSON it would write first. Every write
takes a timestamped backup, refuses outright if the file is not plain JSON,
and lands atomically via a same-directory temp file and `replaceItem`. Belay's
own entries are marked by a query item in its own hook URL, so uninstall is
exact and no unrecognised key is ever added to the user's file. If the file
cannot be edited safely, the UI offers the snippet to paste by hand. The one
write with no button behind it is self-heal, which only repoints entries Belay
already owns at a changed port.

**Power core.** At most one IOKit assertion per kind, process-wide, created with
`IOPMAssertionCreateWithProperties`, a 120 s `kIOPMAssertionTimeoutKey` and
`kIOPMAssertionTimeoutActionRelease`, and re-armed at 75% of that lifetime with
`IOPMAssertionSetProperty`. The reason string is human-readable and shows up in
`pmset -g assertions`. An optional second assertion keeps the display awake, off
by default.

**Safety rails.** A 90 s grace period after the last session goes quiet; a
10-minute session TTL; a 15-minute budget for a session that is only waiting on
the user; a 4-hour cap on one continuous hold; a battery guard that releases
below 20% on battery; and Low Power Mode shortening the grace period rather than
stopping work. The assertion is released on idle transition, quit, `SIGTERM` and
`SIGINT`, system sleep, mode change, battery guard trip and the duration cap. On
wake, the coordinator discards every timestamp it holds and re-derives from
scratch.

**Settings.** Six panes: General, Providers, Behaviour, Notifications,
Statistics and About. Every preference is typed, clamped to a documented range on
both read and write, and stamped with a schema version so a future migration is a
two-line change. A store written by a newer Belay is ignored in favour of
defaults rather than guessed at. Open at login is registered through
`SMAppService`.

**Statistics.** How long Belay has held the Mac awake, how much of that was while
you were away from the keyboard, and how many runs that saved. One bucket per
day, ninety days kept, sampled only while an assertion is held so an idle Belay
schedules nothing. There are no project names and no prompts in it, only
durations and counts, and the numbers stay on the Mac unless you share a card
yourself.

**Notifications.** "An agent is waiting for you", "your agent finished" (for runs
past a 5-minute threshold by default), and a notice whenever a safety rail
releases the assertion. Each blocked session is announced once, not once per
poll. Authorization is requested the first time a notification would actually
fire, never at launch.

**Multilingual.** English, Russian, German, Spanish, French and Italian, in one
String Catalog. Belay follows the Mac's language and falls back to English;
Settings has a picker, and changing it reopens the app, because the menu bar menu
and the alerts are AppKit and will not switch language under a running process.
None of the translations have had a native review yet, which is recorded in
`docs/BLOCKERS.md` B7 and is a wanted contribution.

**Onboarding.** One screen on first launch, dismissible, leading with what Belay
reads and what it does not.

**Scripts.** `scripts/test.sh` (both test commands plus both linters, which is
what CI runs), `build-local.sh`, `perf-soak.sh`, `leak-check.sh`,
`verify-release.sh` and `fake-agent.sh`.

### Security

Detection is entirely local and needs no API key. Belay reads only enough of a
transcript to tell whether it grew and what the last conversational record's
`type` and `stop_reason` were; message content is not decoded. The hook envelope
decoder has fields for `session_id`, `hook_event_name`, `cwd` and
`transcript_path` and nothing else, so the prompt text that `UserPromptSubmit`
carries is never decoded, logged or retained. Request bytes are held in the
receive closure chain rather than on the receiver actor. Session identifiers are
logged `.private`.

The one thing that touches the network is the update check, which asks GitHub
whether there is a newer release. It is on by default and one switch in Settings
under General turns it off; it sends no query and no identifier, and it is absent entirely from the App Store build, which ships
without the `com.apple.security.network.client` entitlement.

### Not in this release

Deliberately deferred to a later version, per `docs/09-MILESTONES.md`: per-session
opt-out, elapsed-time text in the menu bar, Shortcuts and AppleScript support, a
`belay` command-line tool, Focus mode integration, and remote or SSH session
detection.

Claude Code is the only provider with bespoke code. Codex CLI is a preset of the
generic provider rather than a module of its own, because neither `~/.codex` nor
the `codex` binary was present on the machine this was built against and nothing
about its format could be verified. The same is true of every other preset: a
wrong path costs the user one edit and a "needs setup" badge, never a release.

The `belay-hook` command shim that the original detection spec describes as a
fallback delivery path was cut before it was written. See
`docs/adr/003-two-tier-detection.md`.

Two things are built but not finished, and they are listed in `docs/BLOCKERS.md`:
Sparkle is not wired up, so the update check finds a release but cannot install
it, and the translations have had no native review.

[1.2.1]: https://github.com/perfectoweb/belay/releases/tag/v1.2.1
[1.2.0]: https://github.com/perfectoweb/belay/releases/tag/v1.2.0
[1.1.0]: https://github.com/perfectoweb/belay/releases/tag/v1.1.0
[1.0.0]: https://github.com/perfectoweb/belay/releases/tag/v1.0.0
