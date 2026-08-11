# Blockers

Things that need an account or a decision the repository cannot make for
itself, with everything around them already built so that unblocking is a
one-line change. Nothing here stops v1.0 from being complete as
an ad-hoc-signed local build.

B8 is the exception to both halves of that. It is unwritten code rather than a
missing account, and it stops the Mac App Store build from doing its job at all.

---

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
scripts/notarize.sh dist/Vigil-1.0.0.dmg
```

Optional one-time step so the private key is not read off disk each run:

```bash
xcrun notarytool store-credentials VigilNotary \
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

## B4 — App Store name-conflict search for "Vigil"

**Blocks:** nothing yet; due before M6 per `docs/NAMING.md`.

The App Store search has not been done yet. If "Vigil"
collides with a similar utility, the rename is a two-file change
(`project.yml` `PRODUCT_NAME`/`ORG_IDENTIFIER` and
`Sources/VigilApp/Branding.swift`) plus `xcodegen generate`. Ranked alternatives
are in `docs/NAMING.md`.

## B8 — The App Store build cannot read `~/.claude`

**Blocks:** any Mac App Store submission. Does not affect the direct build.

`FileAccessProvider` has exactly one implementation, `DirectFileAccess`, which
calls `FileManager` straight. There is no `bookmarkData`, no
`resolvingBookmarkData` and no `startAccessingSecurityScopedResource` anywhere
in the tree; `FileAccessError.noBookmark` and `.bookmarkUnresolvable` are
declared and never thrown. The seam was designed for this and never filled in.

So `Vigil-MAS` compiles, passes `scripts/verify-mas-build.sh`, and would be
denied every read of `~/.claude` inside the sandbox. A reviewer would see an app
that detects nothing. `docs/06`, `docs/09` M2 and `PROJECT_STATE.md` all describe
the bookmark flow as if it exists.

**Needs:** an open panel that takes a security-scoped bookmark for
`~/.claude`, persistence of that bookmark, and `withAccess(to:)` wrapping every
read in start/stop accessing. Then B2 and the rest of the App Store work.
`docs/APP-STORE.md` has the whole list in the order it has to happen.

Unlike the other entries here, this one is not waiting on an account or a
decision. It is unwritten code, and it is the only blocker on this page that
makes a shipped build lie about what it does.

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
