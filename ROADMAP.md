# Roadmap

Where Belay is going, and what has to be true before each step is worth taking.

This is the product and reach roadmap. The engineering history is
[`docs/09-MILESTONES.md`](docs/09-MILESTONES.md), which is closed through M7, and
the things waiting on an account or a decision are in
[`BLOCKERS.md`](BLOCKERS.md).

Every milestone here has a **gate**: the thing that has to be true first. A
milestone with no gate is a wish, and the point of writing them down is to stop
doing the next thing before the thing it depends on.

## Where things stand, 2026-08-17

| | |
| :--- | :--- |
| Latest release | v1.1.0, 2026-08-14 |
| In flight | 1.2.0, unreleased |
| GitHub | 3 stars, 0 forks, 11 downloads across both releases |
| Repository age | 3 days, public since 2026-08-14 |
| App Store | 1.2.0, developer rejected, waiting on a new build |
| Homebrew | shipping, `brew install --cask perfectoweb/tap/belay` |
| Verified on | macOS 26.4 and macOS 15.0 |

---

## Now

### Ship 1.2.0

**Gate:** the "What's New" screen finished, and the gate green.

Then, in order: tag and release on GitHub, bump the Homebrew cask, upload the
same build to App Store Connect, answer the review thread. Both channels carry
the same number, and the store is set to manual release so the two go out
together rather than whenever a reviewer happens to press approve. The reasoning
is in [`docs/RELEASING.md`](docs/RELEASING.md).

### Get through App Store review

**Gate:** 1.2.0 built and uploaded.

Three findings are already answered: the API used for keeping the Mac awake, the
Apple trademark in the app name, and the entitlement with no matching
functionality. The reply is written and the metadata is in place. What is not
done is the binary.

**This is the fourth attempt.** Two rejections were fair and one was ours to
have avoided. Expect a fourth question rather than an approval, and treat the
answer as part of the work.

---

## Next

### macOS 14

**Gate:** none. It can be done any time.

macOS 15 found three real faults, none of which were expected. That is the whole
argument for running 14 as well: the expectation was wrong last time.
[`docs/QA-CHECKLIST.md`](docs/QA-CHECKLIST.md), `scripts/qa-vm.sh`, and
`BLOCKERS.md` B5.

### Finish or remove Sparkle

**Gate:** a decision, not code.

The framework is in the direct build, signed, with a feed URL and a key. Nothing
in the app drives it, and no appcast is published, so the feed points at a 404
that nobody reaches. Either finish it, with the progress inside Belay's own
settings pane rather than Sparkle's windows, or take the framework back out
until it is wanted. Shipping a signed framework the app never calls is weight
and a signing surface for no return.
[`docs/12-SELF-UPDATING-AND-WHATS-NEW.md`](docs/12-SELF-UPDATING-AND-WHATS-NEW.md).

### Five languages read by people who speak them

**Gate:** finding those people.

German, Spanish, French, Italian and Simplified Chinese are translated and
mechanically tested, and none of them has been read by a native speaker running
the app. Chinese has never been seen running at all. The copy is deliberately
voicier than typical interface text, which is exactly the register a translation
flattens. `BLOCKERS.md` B7.

---

## Reach

The order matters more than the list. Every catalogue below is a first
impression that cannot be made twice, and the ones worth having are the ones
with a bar to clear.

### The catalogues

**Gate:** 1.2.0 released, so the download matches the README somebody just read.

Everything is prepared: which list takes a pull request, which takes an issue
form, which needs an account, and the exact entry text in each one's format.
[`docs/CATALOGUES.md`](docs/CATALOGUES.md).

Two of them have their own gates on top:

- `awesome-claude-code` wants 100 stars **or** 14 days with real commit
  activity. The second opens **2026-08-28**.
- `open-source-mac-os-apps` means OSI approved, which the Belay Source-Available
  Licence is not. One honest attempt, and a no is not a surprise.

### First 100 stars

**Gate:** the catalogues, and one place a person actually reads.

100 is not a vanity number here, it is the key that unlocks the Claude Code
lists, which are the audience that has the problem Belay solves. Three stars in
three days is the honest starting point.

What plausibly moves it: being on `awesome-mac`, being findable when somebody
searches for an Amphetamine alternative, and the app being good enough that the
people who try it tell one other person.

### First 1000 stars

**Gate:** a reason to look, not a place to be listed.

Nothing on a catalogue produces four figures. That comes from one of: a launch
moment spent deliberately, a feature nobody else has, or somebody with an
audience finding it on their own. Product Hunt and Show HN are each one shot per
product, so they are held back for a moment worth spending them on rather than
for a point release.

### First press

**Gate:** something to say that is not "an app exists".

The angle that is actually interesting is not the app, it is the observation
behind it: agents run for hours unattended, Macs sleep on a timer written for
people, and the two facts meet at three in the morning. That is a story. A menu
bar utility is not.

Realistic first stops are the macOS and developer newsletters and blogs that
cover small tools, where a single writer decides. They read the README before
they reply, which is the argument for the README being what it is.

### First large outlet

**Gate:** the small ones first, and numbers that make it worth their time.

A large outlet arrives after the small ones, or after a launch that worked. Not
something to chase directly, and not something to plan around.

---

## Later, and honestly uncommitted

- **Progress inside the app while an update downloads.** Wanted, and blocked on
  the Sparkle decision above.
- **More providers.** Presets exist for Codex CLI, Gemini CLI and Cline; the
  folder watcher covers anything else. Adding a first-class provider is worth it
  only where a tool writes something better than file activity.
- **Tips.** Closed, not deferred: the developer account cannot sign a paid-apps
  agreement, so there is nothing to register. The code was deleted rather than
  left to rot. `BLOCKERS.md` B2.
- **Precise detection in the App Store build.** Possible, and it costs the
  entitlement Apple has now queried twice. Revisit only if people who installed
  from the store ask for it.
