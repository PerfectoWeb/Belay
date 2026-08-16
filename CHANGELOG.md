# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.0] - unreleased

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

**Belay updates itself in one press.** The update row is one button: `Check Now`
when there is nothing to install, and a green `Update Now` with the welcome
screen's wand when there is. It downloads the disk image itself rather than
opening a web page for somebody to find the link on.

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
It now requires the window to be visible. This was `BLOCKERS.md` B9, the
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

**Six languages.** English, Russian, German, Spanish, French and Italian, in one
String Catalog. Belay follows the Mac's language and falls back to English;
Settings has a picker, and changing it reopens the app, because the menu bar menu
and the alerts are AppKit and will not switch language under a running process.
None of the translations have had a native review yet, which is recorded in
`BLOCKERS.md` B7 and is a wanted contribution.

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

Two things are built but not finished, and they are listed in `BLOCKERS.md`:
Sparkle is not wired up, so the update check finds a release but cannot install
it, and the translations have had no native review.

[1.1.0]: https://github.com/perfectoweb/belay/releases/tag/v1.1.0
[1.0.0]: https://github.com/perfectoweb/belay/releases/tag/v1.0.0
