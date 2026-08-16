# Blockers

Things that need an account or a decision the repository cannot make for
itself, with everything around them already built so that unblocking is a
one-line change. Nothing here stopped v1.0 from shipping as a
notarized Developer ID build on 2026-08-13.

B8 was the exception to both halves of that — unwritten code rather than a
missing account, and the one thing that stopped the Mac App Store build from
doing its job at all. It is written now; what is left of it is a run inside a
real sandbox, which no machine here can perform.

---

## The disk image had no background, and nothing about the picture was wrong

Three rebuilds, a hand-drawn volume icon, a folder layout copied from three
shipping installers and a change of volume name all failed to make the
background appear. The artwork was fine the whole time, and so was the
`.DS_Store` this project wrote: the window opened at exactly the size asked
for and both icons landed on the pixel they were told to.

dmgbuild before 1.6.7 writes the background twice. Once as the classic alias
inside `icvp`, which is correct and which Finder has always used, and once as
an `NSURL` bookmark under the key `pBBk`. Finder from macOS 26.2 onwards reads
`pBBk` first, fails to resolve it, and then draws no background at all rather
than falling back to the alias it already has. It keeps honouring everything
else in the same file, which is what makes the fault read as an art problem.
This machine is on 26.4. Upstream removed the bookmark in dmgbuild PR #275,
released as 1.6.7; Blender and Rhino hit the same wall.

Worth keeping in mind for the next one of these: every hypothesis tested was
about our own inputs, the file format, the layout, the volume name, the
quarantine flag. The thing that was actually broken was the tool, and the
evidence for it was sitting in the output the whole time under a four-letter
key nobody had reason to look at.

`release.sh` now refuses to package with a dmgbuild that still writes it, and
checks for the key in the installed source rather than trusting a version
number, because dmgbuild has no `--version` flag to trust.


## What is still needed from the account holder, exactly

Notarization is done and needed nothing. Everything below is for the two things
that are still not automated: a public release, and an App Store submission.

**One App Store Connect API key covers almost all of it.** App Store Connect,
Users and Access, Integrations, App Store Connect API, generate a key with the
**App Manager** role. The `.p8` downloads once and cannot be downloaded again.
Three things come with it: the key file, a **Key ID** and an **Issuer ID**.

Do not paste the `.p8` anywhere. Locally, one command puts it in the keychain
and nothing else ever needs to see it:

```
xcrun notarytool store-credentials belay-appstore \
    --key ~/Downloads/AuthKey_XXXXXXXXXX.p8 --key-id XXXXXXXXXX --issuer YYYYYYYY-...
```

**For GitHub Actions**, these repository secrets:

| Secret | Where it comes from |
|---|---|
| `DEVELOPER_ID_P12_BASE64` | Keychain Access, export "Developer ID Application: David Petrosyan" *with its private key* as .p12, then `base64 -i cert.p12 \| pbcopy` |
| `DEVELOPER_ID_P12_PASSWORD` | whatever password was set on that export |
| `ASC_KEY_ID`, `ASC_ISSUER_ID` | from the API key above |
| `ASC_PRIVATE_KEY` | the contents of the `.p8`, whole file including the BEGIN and END lines |

`VSY2EB4Y9E` is the team ID and is not a secret; it is already in `project.yml`.

**One-time human steps in Apple's web interfaces**, which no key can do:

- Register the App ID `com.perfectoweb.belay` in the Developer portal with the
  App Sandbox capability enabled.
- Create the app record in App Store Connect: name Belay, primary language,
  bundle ID, SKU `belay-mac-1`.
- Add the Mac App Distribution and Mac Installer Distribution certificates to
  this Mac, which the App Store build needs and the Developer ID one does not.

**For updates on the direct channel** (B3), a Sparkle EdDSA key pair. Sparkle's
`generate_keys` puts the private half in the login keychain and prints the
public half, which goes in `Info.plist`. Nothing about it is per-release.

**One thing to install here:** `dmgbuild`, version 1.6.7 or newer, which
`release.sh` requires and refuses to start without. `pipx install
'dmgbuild>=1.6.7'`. It needs Python 3.10 or newer, so the system 3.9 will not
do. An older dmgbuild is rejected by preflight because it leaves the disk image
with no background on macOS 26.2 and later.

With the key in the keychain and `dmgbuild` present, the whole chain runs
from this machine: build, sign, notarize, staple, DMG, GitHub release, and
upload to App Store Connect. Publishing steps stay behind an explicit
instruction each time, because a release and an App Store submission are not
things to do because a script was ready.


## B6 is closed: Belay is notarized

Run on 2026-08-13, submission `ad2ec9b8-bfbb-44d7-9675-7b18ededa008`, verdict
**Accepted**. The app is stapled and `spctl` reports it offline as
`source=Notarized Developer ID`.

No credentials were added for it. The sibling project already had a notarytool
keychain profile called `gibson`, the Apple account is the same one, and a
profile is per-account rather than per-app: `BELAY_NOTARY_PROFILE=gibson` was
the whole of the configuration. The secret stayed in the login keychain and
nothing about it is in this repository.

Two things only a real run could have found, both now fixed:

**The first submission was rejected.** A plain `xcodebuild build` leaves
`com.apple.security.get-task-allow` in the entitlements, which the notary
service refuses, once per architecture. The archive-and-export path
`release.sh` already used strips it. Building for release and building for the
notary are not the same command, and nothing in the script said so.

**The script stopped one step from the end.** It stapled the artefact it
submitted, and a zip cannot hold a ticket: `stapler` refuses. The submission
was already accepted at that point, which is the worst place to stop, because
the work is done and the artefact does not know it. It staples the app inside
the zip now and says to re-zip.

**The whole chain has now been run**, on 2026-08-13: `release.sh` built,
signed, notarized (`bb88c0e2`), stapled and produced `dist/Belay-1.0.0.dmg`,
which `spctl` accepts offline as a notarized Developer ID app. It found one
more fault of its own on the way.

`set -o pipefail` and `grep -q` do not get along. The hardened-runtime check
piped `codesign` into `grep -q`, which exits the instant it matches, and
`codesign` then dies of SIGPIPE and takes the pipeline's exit status with it.
The script refused to package a correctly hardened app, and the message it
printed said the opposite of what was true. It reads the output into a
variable now.

The archive also warned that no `LSApplicationCategoryType` was set, which the
App Store requires and which was on the checklist as a separate item. It is
`public.app-category.developer-tools`, in `project.yml`, for both channels.


## The notification icon is a placeholder on this Mac, and I cannot say why

Notification Center draws macOS's generic "unknown app" square instead of
Belay's icon. Ruled out, each by building it and watching a real notification
fire:

- **The bundle.** `NSWorkspace` resolves the icon from `/Applications/Belay.app`
  correctly at 32, 64, 80 and 128 px. 80 px is roughly what a notification
  draws. `Assets.car` carries AppIcon at all ten sizes and `CFBundleIconName`
  and `CFBundleIconFile` are both set.
- **LaunchServices ambiguity.** Nine copies of this bundle identifier were
  registered, one at a path that no longer existed. Cleaned down to one, still a
  placeholder. `build-local.sh` now registers each fresh build so it cannot
  drift back.
- **The external volume.** Copied to `~/Applications` and then to
  `/Applications`. Same placeholder from all three.
- **The truncated `.icns`.** The one Xcode emits holds four representations, not
  ten. Replaced it with a complete one built by `iconutil`. No change.
- **Ad-hoc signing.** Re-signed with the Developer ID certificate, hardened
  runtime and the real entitlements. No change.

- **The asset catalogue as the only source.** Deleted `AppIcon.icns` and its
  Info.plist key from a copy, leaving `Assets.car` alone to answer. Renders
  byte-identically at 32, 64, 80 and 128 px. The catalogue is not the problem
  either.

The cache theory is dead. A clean macOS 15.0 VM that had never granted Belay
notification permission shows the same placeholder, so this is ours and not one
machine's leftovers.

What both machines still have in common is where the app was: `/Volumes/BASE`
here, `~/Desktop` there. `usernoted` is sandboxed, and reading an app bundle out
of a user folder is exactly the kind of thing it would be refused. `/Applications`
was tried here, but only after this Mac had already answered wrong once, so it
proves less than it looked like at the time. The clean test is `/Applications`
on the VM, which is also where a real user would put it.


## B1 — RESOLVED (2026-08-10)

Team ID **VSY2EB4Y9E**, read from the `Developer ID Application: David
Petrosyan (VSY2EB4Y9E)` certificate that is present in the login keychain.
`DEVELOPMENT_TEAM` is now set in `project.yml`.

A Developer ID signed build has been produced and verified:

```
TeamIdentifier=VSY2EB4Y9E
flags=0x10000(runtime)            hardened runtime on
Timestamp=10 Aug 2026 19:43:07    secure timestamp present
codesign --verify --deep --strict  satisfies its Designated Requirement
spctl -a -t exec                   rejected: "Unnotarized Developer ID"
```

That step is done. See B6: `spctl` reports the shipped app and the disk image
both as `source=Notarized Developer ID`, and both carry a stapled ticket, so a
first launch needs no network.

## B2 — CLOSED (2026-08-16). The tip jar is not happening on this account

Not a technical block and not something a product identifier would fix. The
developer account is Russian, and paid items are not available to it, so there
is nothing to register.

The StoreKit code was deleted on 2026-08-16. It had been written, tested and
never called, and a seam nobody walks through is not free: it is a module to
keep compiling, a flag to check before every submission, and a thing a reviewer
could find. The git history keeps it, which is where an unused implementation
belongs. What stayed is `BelayChannel`, which answers the question the app
actually asks: which build is this.

## B2, as it was — StoreKit IAP product identifiers (Mac App Store tip jar)

**Blocks:** the tip jar in the MAS build.
**Does not block:** the direct build, which uses a plain support link behind the
same `TipJarProviding` protocol.

Consumable product IDs cannot be registered without the user's App Store Connect
account. They are declared as placeholders in one constants file and the tip UI
is behind a feature flag that stays off until real products exist.

## B6 — RESOLVED (2026-08-13). Kept for the credential reference below

**Blocks:** nothing locally. An ad-hoc or Developer ID signed build runs fine on
this Mac. It matters when the app is given to someone else.

Credentials are in place (App Store Connect API key, `.secrets/`, key id
the key id is in `.secrets/`, not here). `scripts/notarize.sh` uses a
notarytool keychain profile if one
exists and otherwise falls back to that key, so no setup step is required.

Not run yet because notarization uploads the binary to Apple, which is an
outward-facing action on the owner's account. To do it:

```bash
scripts/release.sh                       # archive, export, package, notarize
# or, on an artefact you already have:
scripts/notarize.sh dist/Belay-1.0.0.dmg
```

Optional one-time step so the private key is not read off disk each run:

```bash
xcrun notarytool store-credentials BelayNotary \
  --key .secrets/AuthKey_<KEY_ID>.p8 \
  --key-id <the key id from .secrets/> \
  --issuer <ISSUER_ID>   # both live in .secrets/appstoreconnect.env, which is gitignored
```

## B3 — RESOLVED (2026-08-16), and finished (2026-08-17)

The app now drives Sparkle: `SoftwareUpdate` owns the updater and `Update Now`
hands it the job, so a new version downloads with a progress bar, is checked
against the public key in this build, and is swapped in. `SUEnableAutomaticChecks`
is false, so the only scheduled network access is still Belay's own daily check.

**One thing is not done, and it needs a person.** No appcast is published yet, so
the feed URL is a 404 and Update Now would find nothing.
`scripts/publish-appcast.sh --publish` does the whole job, and stops in the
middle for a Keychain dialog: `generate_appcast` reads the EdDSA private key,
and macOS asks whether it may. Answer "Always Allow" once. Everything before and
after that dialog has been run and works.

## B3, as it was — the key, the feed, and the channel split

The key exists in the release machine's login Keychain; its public half,
`Vzv5S2MFDz1si7eu25uDdjAYO/wDqwsA+Y2iDU0c3e8=`, is in the direct build's plist,
which is where it belongs and where anybody can read it. The private half was
never printed into a log, a file in this repository, or a conversation.

The feed is `https://perfectoweb.github.io/Belay/appcast.xml`, on the `gh-pages`
branch that already publishes the site: one push updates both, and there is no
second host to keep alive.

Three things worth knowing before touching any of it again:

**The Info.plist had to be split.** It was shared by both targets, and the note
beside it predicted that the first key to differ by channel would be
`SUFeedURL`. It was. There are now `Info-Direct.plist` and `Info-MAS.plist`,
generated from `project.yml`, and `Info*.plist` is excluded from the app's
sources so neither target picks the other's up as a bundle resource.

**The App Store build is still clean.** `verify-mas-build.sh` was run after the
change: no Sparkle framework, no Sparkle symbols or load commands, no
`SUFeedURL`. The direct build does carry `Sparkle.framework` and the feed URL.

**The private key cannot be rotated.** A client running an old build verifies
against the public key compiled into *that* build, so a new key would be
rejected by everyone who has not already updated. Losing it does not mean
issuing a new one; it means every existing user is stranded on the version they
have and has to reinstall by hand. Back it up somewhere that is not this
repository and not this machine.

## B4 — CLOSED (2026-08-16). The search was done and there is no conflict

## B4, as it was — App Store name-conflict search for "Belay"

**Blocks:** nothing yet; due before M6 per `docs/NAMING.md`.

The App Store search has not been done yet. If "Belay"
collides with a similar utility, the rename is a two-file change
(`project.yml` `PRODUCT_NAME`/`ORG_IDENTIFIER` and
`Sources/BelayApp/Branding.swift`) plus `xcodegen generate`. Ranked alternatives
are in `docs/NAMING.md`.

## B8 — RESOLVED (2026-08-12). The click was run and it worked

**Was:** the App Store build could not read `~/.claude` at all. `FileAccessProvider`
had one implementation, `DirectFileAccess`; nothing in the tree created or
resolved a bookmark, and `FileAccessError.noBookmark` and `.bookmarkUnresolvable`
were declared and never thrown. `Belay-MAS` compiled, passed
`scripts/verify-mas-build.sh`, and would have shown a reviewer an app that
detects nothing.

**Now:** `BelaySupport.BookmarkFileAccess` is the sandboxed implementation, and
`Tests/BelaySandboxTests` is a test bundle hosted by `Belay-MAS`, so it runs in
that app's own container. `scripts/test.sh` runs it. What it proves, for real:

- the host is sandboxed — `NSHomeDirectory()` is the container;
- `homeDirectoryForCurrentUser` is the container and `UserHome.real` is not,
  which is the trap that caused the original bug;
- an app-scoped bookmark is created, stored, and resolved by a second
  `BookmarkFileAccess` that then reads a file through it. This needs the
  `files.bookmarks.app-scope` entitlement and real Foundation calls on both
  sides, so the entitlement, the round trip and the resolve are all exercised.

**What it does not prove, and the reason is worth knowing.** Hosting an XCTest
bundle in a sandboxed app *changes that app's sandbox*: Xcode injects
`com.apple.security.temporary-exception.files.absolute-path.read-only` for `/`
into the test host, next to the mach-lookup exceptions the runner needs. So
inside this harness no file read is denied anywhere, and any test asserting
"without a grant `~/.claude` cannot be read" passes for the wrong reason. Two
versions of that test were written and both were wrong before the entitlements
were dumped and read. `testTheTestHostIsGrantedReadsTheShippingBuildIsNot` now
asserts the injection is there, so the next person finds this in seconds; it
also asserts our own entitlements file has no exception, which
`scripts/verify-mas-build.sh` confirms on the built Release binary.

**Done by hand, 2026-08-12**, on a Release MAS build with no test bundle: the
Providers pane asked, the panel took `~/.claude`, the pane went to ready, and a
quit and reopen did not ask again. The evidence is a 660-byte
`BelayClaudeFolderBookmark` in the container's own preferences — something only
the sandboxed build can write. `docs/QA-CHECKLIST.md` §9 records it.

## B9 — RESOLVED (2026-08-13). It was the settings window, found by name

Run #1 on the public repository failed with "181 tests in 30 suites failed with
1 issue" and run #2, with nothing changed, passed. Twenty consecutive local runs
with the machine loaded were green, so it stayed unidentified.

It turned up on release day, three times in a row, on a laptop that had just had
the app opened and closed repeatedly for smoke testing:
`PresetDuplicationTests.testTheSheetHasTheSettingsWindowToHangOff`, asserting
that the window the folder sheet would hang off is the settings window it just
made.

`GenericTargetsSection.hostWindow` found that window with
`NSApp.windows.first { $0.identifier == SettingsWindow.windowIdentifier }`. A
closed settings window stays in `NSApp.windows` until AppKit lets go of it, so a
process that has opened settings more than once has two windows wearing that
identifier and `first` is a coin toss. Which is why it was intermittent, why
load never reproduced it, and why a CI runner — different order, different
timing — was where it first showed.

The fault was never in the test. Losing that toss in the shipped app attaches
the folder picker to a window nobody can see, which reads to a user as the
picker simply not opening. `hostWindow` now requires `isVisible`, which is what
it always meant. Four consecutive suite runs green afterwards.

**A flaky gate is worse than a red one:** it teaches people to press re-run, and
a real regression then hides among the false alarms. This one was hiding a real
regression the whole time.

## B7 — five languages left, not seven

English and Russian have been read by someone who speaks them. What is still
unreviewed is **German, Spanish, French, Italian and Simplified Chinese**, and
Chinese is the one that has never been seen running at all.

Six languages ship: en, ru, de, es, fr, it. All 210 strings are translated and
`LocalizationTests` guards the mechanical half — every offered language present
in the bundle, no empty tables, no wholesale copies of English, and format
specifiers matching the source.

What is **not** verified is whether the German, Spanish, French, Italian and
Russian read well. This app's copy is deliberately voicier than typical
interface text ("and not a minute longer", "a control that lies about having
worked"), which is precisely the register a non-native translation flattens or
gets wrong. Nothing here is machine-translated, but one careful pass by one
person is not review.

One thing this did catch, on 2026-08-13, from someone switching the app between
languages and looking: the three mode names in the panel picker are the strings
a long translation breaks first, because all three sit side by side in one 330pt
panel. Measured against the tab they have to fit in, Spanish was four points
over and was being truncated on Spanish Macs and nowhere else. Italian and
French were inside it by less than two points. They are shortened now, and
`testEveryModeNameFitsItsTab` measures every language against the same numbers
the view lays out with, so the next translation cannot quietly overflow.

Note what that says about the rest: nothing in the build, the tests or CI knew.
It took a person changing the language and looking at the result.

**Needs:** a native speaker per language, reading the app rather than the
catalogue. Highest value on the strings a new user meets first — the onboarding
pane, the panel status line, and the About tagline.

Until then this is a quality risk, not a correctness one: every string resolves,
nothing crashes, and English remains the fallback for anything unsupported.

## B5 — macOS 14 verification. 15 is done

**Blocks:** the "runs clean on 14 / 15 / 26" claim in `docs/00-INVARIANTS.md`.
**Does not block:** development. The deployment target is 14.0 and every API
newer than that is behind an `@available` guard.

macOS 15.0 (24A335) was run on 2026-08-16 in a Parallels VM on Apple silicon,
with `scripts/qa-vm.sh` plus the two things only eyes can check. It found three
real faults, all fixed and all in `main`: the assertion was not released on
quit, the welcome window opened off-centre because its size was read before
layout, and the Skip button was a system push button there while every other
button in the app is drawn. The rerun after those fixes was clean.

macOS 14 is the one left. Nothing about it is expected to differ, which is
exactly why it is worth running: 15 was not expected to differ either.
