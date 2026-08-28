# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.6.3] - 2026-08-28

### Fixed

- Precise Detection survives a restart. The hook receiver took an ephemeral
  port, so every launch moved it and the agent kept posting to the address its
  settings file still named. During a Sparkle update the move is certain: the
  outgoing instance is still holding the socket when the new one binds.
  Reported from the field on 28 Aug, where 61716 became 61717 and the agent's
  terminal filled with `ECONNREFUSED` for three hours; reproduced here as
  49680 becoming 49683 on an ordinary restart. The receiver now asks for the
  port recorded in `bridge.json`, retries four times a quarter-second apart
  while the previous instance lets go, and only then settles for a free one.
  A first run picks from 41000–42999 rather than the ephemeral range, which is
  where macOS puts outgoing connections and so the one range where a recorded
  port can be taken by a browser or a build tool while Belay is closed.
- The diagnostics log finally says something about the bridge: `bridge up
  port=N`, `bridge port busy, retrying`, `bridge did not start: …`, and a line
  for each settings file it repoints. The one subsystem whose failure a person
  sees in their own terminal was the one the log they send us said nothing
  about.

### Changed

- The longer lists behind Shift open on Option as well. Option is what macOS
  itself uses for alternates, so somebody wondering whether a menu is hiding
  anything reaches for it without being told; Shift keeps working because it
  is what 1.6.2's notes describe in seven languages.

## [1.6.2] - 2026-08-27

### Fixed

- A tool call that runs for a long time no longer reads as a finished turn
  (risk R6). A `PreToolUse` with no `PostToolUse` after it is not a stale
  reading but an unclosed bracket, so while one is open the exact reading keeps
  its rank however old it is, the session is exempt from the ledger's TTL, and
  the hold survives a half-hour test run. Bounded by
  `AwakePolicy.openToolCallBudget` (one hour) for the case where an agent is
  killed between the two hooks, with the process sweep and the awake limit
  above it.
- The busy-child sweep walks the agent's whole process tree instead of its
  direct children. Claude Code runs its Bash tool inside one long-lived shell,
  so the process doing the work is a grandchild and the old probe saw an old
  shell and nothing else. Breadth-first, depth-capped, same age bound as
  before. This is the half of the fix that works without hooks, which is the
  only half the App Store build has.
- The diagnostics log stops repeating itself. Consecutive identical lines are
  counted rather than written, and the count lands on a widening interval, a
  minute out to an hour. An unreachable lid helper wrote the same sentence
  every fifteen seconds: 5 760 lines a day, none of them saying anything the
  first had not.
- `scripts/build-local.sh` produces a bundle that launches again. It signed
  everything with `--options runtime`, and the hardened runtime's library
  validation asks that everything a process maps carry the same team ID; an
  ad-hoc signature has no team at all, and dyld reads two absent team IDs as
  two different ones. `codesign --verify` passed while the app died at launch.
  The hardened runtime is now applied only when a real identity is given.

### Added

- Longer sleep delays, behind Shift: 15 minutes, 30 minutes and an hour join
  the five ordinary choices while the key is held, the way the Always On timer
  already works. The chosen value stays visible afterwards, held or not.
- An agent's tile menu gained a Precise Detection submenu holding Rules… and
  Turn Off. Rules… opens the preview of what Belay writes into the agent's
  settings and applies it in place, so reviewing the rules no longer means
  removing detection and adding it back. Direct build only.

## [1.6.1] - 2026-08-26

### Fixed

- A rare overnight crash. With Keep local reports on, every log line left the
  diagnostics sink one closure wrapper deeper (a generic-inout reabstraction
  writing the wrapped copy back), so a night of steady agent traffic built a
  stored callback thousands of frames deep and the next write overflowed the
  cooperative pool's stack — SIGBUS, no crash dialog. The sink now lives in a
  class box that reabstraction cannot touch, with a regression test that calls
  it ten thousand times and measures the depth.
- A killed Belay is visible now: every graceful exit writes `collection off`
  (including the `killall` path, which exits before
  `applicationWillTerminate`), and the next launch names a session that never
  said goodbye.
- Cline sessions in custom watched folders under `/tmp`- and `/var`-style
  paths were invisible: FSEvents hands back `/private`-resolved paths while
  Foundation's resolver strips the prefix, so the root prefix check failed.
  Both sides now go through the same resolver.
- Sharing the statistics card to Telegram and friends attaches the image
  again: the card ships as a file URL, which share extensions accept where a
  raw image object was dropped.

### Added

- The custom timer dialog takes a length ("For") or a wall-clock end time
  ("Until") — a time already past means tomorrow — with a footnote showing
  the other reading live, a mode switch that slides like the main picker, and
  the dialog rides the panel as a sheet instead of opening behind it.
- The erase-statistics dialog offers a CSV export of every recorded day
  before anything is deleted.
- The Statistics headline flips to held-while-you-were-here on hover, and
  chart bars trade their weekday for the date under the cursor.

### Changed

- Switched-off agent tiles dim as one piece, options icon included; the Off
  pill sits back in dark mode (plain grey, full contrast kept under Increase
  Contrast); mode-picker and timer-dialog tabs hold their colour while
  pressed; the statistics footer aligns Reset and its privacy line with the
  share buttons.

## [1.6.0] - 2026-08-25

### Added

- Copilot CLI is a built-in agent. Switch it on in Settings and Belay follows
  its sessions by their own event log — explicit turn markers, no hooks to
  install. The dead-process sweep only trusts the absence of a `copilot`
  process it has actually seen, so npm installs running under another name are
  never reaped by mistake.
- Watched folders for every built-in agent (#4). Agents that relocate
  (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `CLINE_DIR`, `COPILOT_HOME`) and
  multi-profile setups are covered by adding each folder from the agent's tile
  menu: one provider instance per folder, the open panel doubling as the
  sandbox grant in the App Store build. The direct build also suggests sibling
  profiles found next to the default home. Precise Detection covers every
  watched folder — enabling installs hooks into each, a folder added later is
  installed into automatically, and a removed folder takes its hooks with it
  behind a confirmation.
- The Always On timer survives a relaunch: it resumes exactly where it was,
  and one that expired while Belay was closed lands in the pause with Hold
  Again.
- Agent tiles show live last activity for every agent, updating as sessions
  come and go.
- The Release Flow workbench gained a GitHub tab: the release announcement is
  reviewed and edited there before anything goes public.

### Changed

- The tile's options button (and right-click) opens one menu: Precise
  Detection controls and Watched Folders, each added folder with Show in
  Finder and a destructive Remove behind a confirmation dialog.
- Built-in tiles glow softly under the cursor while enabled; switched-off
  tiles dim as one piece and stay unlit.
- The About footer reads "Free & open code", matching the licence's no-selling
  terms; docs/TRADEMARKS.md no longer contradicts them.
- Night dimming's time fields lost their border, centred their digits, and the
  dash hugs its fields.

### Fixed

- A full audit of the codebase, every fix with a regression test:
  - A malformed local request could crash the receiver and drop the sleep
    assertion with it.
  - Synchronous helper-status reads froze the main thread at launch and in
    Settings (the third time this class of bug shipped; all paths are off-main
    now).
  - Claude Code subagents no longer pin the Mac after their CLI dies: reaping
    the main session takes its subagents with it.
  - A power assertion the kernel reaped is re-created instead of being
    re-armed on a dead handle forever.
  - The awake limit no longer counts time the Mac spent asleep, and a
    backwards clock step (an NTP correction) resyncs instead of over-holding.
  - A resumed session survives its crashed predecessor's leftover pid file.
  - Cline teammates survive file truncation; per-run webhook watches retire
    instead of accumulating; phantom "ended" rows are gone for every provider.
  - The hook installers refuse to overwrite foreign config of any shape, the
    bridge record is written atomically, and the lid helper never raises the
    sleep flag it could not record how to lower.
  - Notification permission granted after a first refusal is noticed without a
    relaunch; `killall Belay` banks the running hold into Statistics.
  - Reduce Motion is honoured by the onboarding starfield; the night-dimming
    clock fields render correctly in light mode; the mode picker's selected
    label meets contrast on every pill.

## [1.5.0] - 2026-08-24

### Added

- Cline is a built-in agent. Switch it on in Settings and Belay follows
  Cline's sessions by their own state files — including team mode: teammate
  agents appear in the panel under their session, the way Claude Code
  subagents do.
- Precise Detection for every agent, in the direct build. Codex gets command
  hooks in `~/.codex/hooks.json` (Belay also records their approval in
  `config.toml`, because Codex silently skips unapproved hooks); Cline gets
  one small script per event in `~/.cline/hooks`. Each agent's tile offers
  Enable Precise with a full preview of what will be written, and
  Control-click removes it. Every install is backed up first and self-heals
  when the receiver's port changes.
- The consent sheet shows the agent's own mark, opens with a plain sentence
  about what precise detection buys, and keeps one height for every agent.

### Changed

- The Agents pane is built around the agents themselves: each tile carries
  its switch, its detection status (Standard or Precise, with the last
  activity), and its precise controls. The separate precise-detection row is
  gone.
- A copy pass across Settings: Behavior, Notifications and Agents read
  shorter and plainer, in all seven languages.
- The agent switches are drawn by Belay, so their first frame always shows
  the true state.

### Fixed

- Sessions touched by other apps' importers no longer wake the panel: both
  transcript watchers now trust the records' own clocks over file
  modification times.
- Running the test suite can no longer disturb a running Belay: the test
  host stays inert instead of launching the full app.
- The Russian pause line no longer wraps and jumps the panel's height.

## [1.4.0] - 2026-08-24

### Added

- Always on can hold for a chosen while. A quiet row under the mode picker
  offers 15 minutes to 12 hours, or the usual "until turned off", and counts
  the remaining time down as `HH:MM:SS`. Hold Shift — before opening the
  menu or while it is open — and the list doubles to fourteen steps, from
  45 minutes to 14 hours. When the timer runs out Belay lets go, says so,
  and the same row offers "Hold again" for another round.
- The pause has a one-click exit. When the maximum-awake limit or a timer
  ends a hold, the row under the picker names the pause and "Hold again"
  starts a fresh cycle, in Auto as well as Always on. A tripped limit also
  re-arms on its own when you unlock the screen or wake the display; a
  finished timer does not, because "this long" was a deliberate choice.
- The dimmed screen shows the countdown. While an Always on timer runs and
  the night dimmer has the display down, the remaining time sits in large
  thin white digits in the middle of the screen. The gamma ramp dims the
  digits with everything else, so they read as cut out of the dark; they
  drift a few points a minute for OLED panels, take no clicks, and can be
  turned off beside the dimming controls.
- The statistics chart plays its outline: sweep the cursor across the last
  fourteen days and every bar strikes a note from a pentatonic run, pitched
  by its height. Empty days stay silent.
- Claude Code and Codex each have a switch in Settings. A switched-off agent
  is not started, not watched, and never asks for a folder; switching one on
  is the moment Belay asks, if this build has to. On first launch the direct
  build switches on the agents whose folders exist. "Start Magic" on the
  welcome screen now opens Settings on Providers.
- What's New is a card: the wordmark, a version pill, four rows with
  outlined icons, and one button. Blocks arrive one after another from the
  top; the television switch-on is gone.

### Changed

- The dimmer explains when it actually dims: the sentence in Settings now
  quotes the system's display-off delay — "after 10 min on power right now"
  — and says so when the display is set never to turn off. Defaults for new
  installs: 20 percent, 22:00 to 10:00.
- A Mac without Codex is told "Codex is not installed", never "allow access
  to ~/.codex": the direct build can tell an absent folder from an
  unreadable one and no longer mistakes the first for a missing grant.
- The panel stays put: the mode pill slides on its own, nothing jumps when
  the timer row appears, and a click anywhere outside closes the panel
  even after its menu has been used.

### Fixed

- The CI release job yields when the tag already has a release instead of
  failing red; the local ritual's artefacts stay canonical.
- The test gate no longer hangs on a TCC prompt while sweeping scratch
  preferences out of the sandbox container.

## [1.3.3] - 2026-08-20

### Fixed

- Finished turns release within seconds instead of five minutes. Claude
  Code's `SubagentStop` hook fires a few seconds after the turn's own `Stop`,
  and its lone "working" signal kept the exact tier fresh for the whole
  five-minute window — the cause of every "still Working after it finished"
  sighting this release chased. It yields no signal now; parents' own events
  and the subagents' watched transcripts carry the hold mid-turn.
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
