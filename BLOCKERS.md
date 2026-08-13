# Blockers

Things that need an account or a decision the repository cannot make for
itself, with everything around them already built so that unblocking is a
one-line change. Nothing here stops v1.0 from being complete as
an ad-hoc-signed local build.

B8 was the exception to both halves of that — unwritten code rather than a
missing account, and the one thing that stopped the Mac App Store build from
doing its job at all. It is written now; what is left of it is a run inside a
real sandbox, which no machine here can perform.

---

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

Still owed before a public download: `create-dmg` is not installed on this
machine, so `release.sh` refuses to start and the DMG half is unproven. The
zip is notarized and distributable as it stands.


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

That last line is the expected and only remaining step: the app is correctly
signed, and Gatekeeper wants a notarization ticket before it will run without a
prompt on a machine that did not build it. See B6.

## B2 — StoreKit IAP product identifiers (Mac App Store tip jar)

**Blocks:** the tip jar in the MAS build.
**Does not block:** the direct build, which uses a plain support link behind the
same `TipJarProviding` protocol.

Consumable product IDs cannot be registered without the user's App Store Connect
account. They are declared as placeholders in one constants file and the tip UI
is behind a feature flag that stays off until real products exist.

## B6 — Notarization has credentials but has never been run

**Blocks:** nothing locally. An ad-hoc or Developer ID signed build runs fine on
this Mac. It matters when the app is given to someone else.

Credentials are in place (App Store Connect API key, `.secrets/`, key id
`U43BKFM82D`). `scripts/notarize.sh` uses a notarytool keychain profile if one
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
  --key-id U43BKFM82D \
  --issuer <ISSUER_ID>   # both live in .secrets/appstoreconnect.env, which is gitignored
```

## B3 — Sparkle EdDSA signing key and appcast hosting URL

**Blocks:** shipping automatic updates in the direct build.
**Does not block:** building or running. The update check is behind
`UpdateChannel`, whose no-op implementation is used until a feed URL exists.

The private key belongs in the user's Keychain and must never enter this repo.
`scripts/sign-update.sh` wraps `generate_appcast` and expects it there.

## B4 — App Store name-conflict search for "Belay"

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

## B9 — One module test fails intermittently on CI and has not been identified

Run #1 on the public repository failed with "181 tests in 30 suites failed with
1 issue". Run #2, with no change to any test or any line of production code,
passed. So a suite is flaky on the GitHub runner.

Not reproduced locally: 20 consecutive runs of the module suites, with every
core but one saturated to imitate a throttled shared VM, were green 20 out of
20. CPU contention is therefore not the trigger. What is left is the rest of the
runner environment: a slower filesystem under FSEvents, cold caches, or the
older toolchain's test runner.

The name is unknown because a CI log scrolls the failing test off the top and
the Actions log API needs a token even on a public repository. `scripts/test.sh`
now reprints failures at the end and emits them as `::error::`, which becomes a
GitHub annotation readable without auth, so the next occurrence identifies
itself.

**A flaky gate is worse than a red one:** it teaches people to press re-run,
and a real regression then hides among the false alarms. This should be found
before the repository takes outside contributions.

## B7 — Translations have had no native review

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

**Needs:** a native speaker per language, reading the app rather than the
catalogue. Highest value on the strings a new user meets first — the onboarding
pane, the panel status line, and the About tagline.

Until then this is a quality risk, not a correctness one: every string resolves,
nothing crashes, and English remains the fallback for anything unsupported.

## B5 — macOS 14 and 15 verification

**Blocks:** the "runs clean on 14 / 15 / 26" claim in `docs/00-INVARIANTS.md`.
**Does not block:** development. The deployment target is 14.0 and every API
newer than that is behind an `@available` guard.

Only macOS 26.4 was available here. `docs/QA-CHECKLIST.md` lists what to run on
a 14 and a 15 VM.
