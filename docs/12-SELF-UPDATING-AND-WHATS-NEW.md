# Self-updating, and the "What's New" screen

Two features and the work each of them actually needs. Written down before any
of it started, because both have a shape that is easy to get wrong and
expensive to change afterwards.

This was `12-V1.2-PLAN.md`. There was no 1.2: the number was skipped and the
next release is 1.3.0. The file is named for what it is about instead, since a
plan named after a version is wrong the moment the version moves.

**Part 2 is built and in `main`.** Part 1 is half built: Sparkle is in the
direct build and configured, but nothing in the app drives it yet. See the
status note under it.

Already in `main`, waiting for the release:

- The update row is one button. When there is nothing to install it says
  **Check Now**; when there is, it becomes a green **Update Now** with the wand
  from the welcome screen and opens the download.
- Folders picked for a generic target are remembered with a security-scoped
  bookmark each, so the sandboxed build can read them at all, and can still
  read them on the next launch.
- The disk image no longer shows `.background.tiff` and `.VolumeIcon.icns` in
  the middle of the artwork. This one only reaches people through a new
  release: 1.1.0 cannot be rebuilt without changing the checksum Homebrew has.

---

## 1. Updating itself, with a progress bar

**Status.** `Update Now` downloads the disk image itself now rather than opening
a page, which is the useful half. Sparkle is in the direct build with its feed
URL and public key in `Info-Direct.plist`, the signing key exists, and
`verify-mas-build.sh` keeps it out of the App Store build. What does **not**
exist yet is any code that drives it: there is no `SPUUpdater` anywhere in
`Sources`, and no `appcast.xml` is published, so the feed URL currently points
at a 404. Nobody reaches it, because nothing asks.

That is the decision left: finish it, or take the framework back out until it is
wanted. Shipping a signed framework the app never calls is weight in the bundle
and a thing to keep signing correctly for no return.

The wanted behaviour is: press it, watch the download, then be offered a
restart, or be restarted.

### Do not write the downloader

Replacing a running app with a newer copy of itself is a solved problem with a
long list of ways to get it wrong, and every one of them ends with a Mac that
has a broken app on it:

- the archive has to be verified before it is trusted, not after;
- the running app cannot overwrite its own bundle while it is running;
- the replacement has to keep its quarantine and signature state, or Gatekeeper
  refuses the new copy on the next launch;
- if the machine loses power in the middle, what is on disk has to be either
  the old app or the new one and never half of each;
- the relaunch has to survive the old process exiting.

**Sparkle** does all of that, and the project is already built around it: the
package block is written and commented out in `project.yml`, the app talks to
updates through `UpdateChannel`, and `scripts/sign-update.sh` exists. This
feature is not "write an updater", it is "turn Sparkle on".

### What turning it on needs

| Step | Where | Notes |
|---|---|---|
| Generate the EdDSA key | The maintainer's Mac | `generate_keys` from Sparkle. The private key stays in the login Keychain and never enters this repository |
| Host the appcast | `gh-pages` | `perfectoweb.github.io/Belay/appcast.xml`. The site already publishes from that branch, so there is nothing new to run |
| Uncomment the package | `project.yml` | The block at lines 39-49, the dependency on the Belay target, and `SUFeedURL` in that target's Info.plist. It is written to be exactly these three edits |
| Sign each release | `scripts/sign-update.sh` | Run after `release.sh`, like `bump-cask.sh`. It appends the new version to the appcast and signs it |
| Keep it out of the App Store build | Already enforced | `verify-mas-build.sh` fails if a Sparkle symbol appears in the MAS binary. Apple rejects third-party updaters |

That closes `BLOCKERS.md` B3.

### The progress bar is a separate decision

Sparkle brings its own windows. They are competent and they look like Sparkle,
not like Belay. Keeping the progress inside our own Settings pane means
implementing `SPUUserDriver`, which is a protocol of about a dozen callbacks:
Sparkle drives the download and the install, and hands us "here is the
progress", "here is the release note", "ready to relaunch".

That is the part worth doing carefully, and it is worth doing after the plain
Sparkle path works end to end. Shipping the standard UI first proves the key,
the appcast and the install; replacing the UI afterwards changes nothing about
whether an update can be installed.

### The App Store build does not do any of this

It must not, and it does not need to: the App Store updates its own apps.
`ReleaseChecker` already returns `isSupported = false` under `BELAY_MAS`, so
that build shows no update row at all. If it should ever point somewhere, it
points at the App Store page and nowhere else.

## 2. A "What's new" screen

**Status: built.** `Sources/BelayApp/WhatsNew/`, with the decision table in
`WhatsNewDecision` and a test per branch of it. What follows is the plan it was
built from; three things came out differently and are marked where they are.

Shown once, on the first launch after an update, in place of the welcome screen.
Somebody who has never run Belay gets the welcome screen; somebody who has, and
has just moved to a newer version, gets what changed.

### The rule that decides which

Belay already stores `hasCompletedOnboarding`. That is enough to tell a first
run from any other, but not enough to tell an update from an ordinary launch.
That needs one more thing remembered: **the version that was last seen**.

| Last seen | Onboarding done | What opens |
|---|---|---|
| nothing | no | The welcome screen, as today |
| nothing | yes | Nothing. Somebody who has used Belay before the key existed is not new, and must not be told about a version they may have been running for months |
| older than this build | yes | What's new |
| this build | yes | Nothing |

The middle row is the one that needs care: the key does not exist yet, so on the
first launch after 1.2 arrives every existing user has no last-seen version. If
that is read as "new user", every one of them gets the welcome screen again.
Write the current version at the end of onboarding **and** on any launch that
finds the key missing but onboarding already done.

### What it shows

Same window and same chrome as the welcome screen. It is not a new surface, it
is the same panel with different content, and it needs the same one way out.
That part held: `PanelWindow` builds both, so the sizing and centring fixes
cannot drift apart.

Three things came out differently from this plan:

**The content is not taken from the changelog.** The plan said it should be, to
avoid two lists drifting. In practice they are two different documents: the
changelog is the record, in English, at whatever length each fix deserved, and
the screen is the announcement, translated into seven languages, three to five
lines long. Sharing a source would have given the screen the changelog's length
and vocabulary. `ReleaseNotes` is the announcement, and adding a release means
writing its lines and translating them, which is a real cost and is written down
where somebody adding one will read it.

**It shows more than one version.** The plan said this version only. Belay
updates on the user's schedule rather than a store's, so skipping a release is
ordinary, and everything newer than what somebody last saw is what they have not
seen. The list is capped at six items and trims from the oldest end; the version
just installed is never trimmed.

**There is no scroll view.** Two attempts had one, and both clipped the last
item mid-sentence: a `ScrollView` has no height of its own to report, so a window
sized from its content gets a guess. The window grows with the list instead,
which is why the item cap exists.
