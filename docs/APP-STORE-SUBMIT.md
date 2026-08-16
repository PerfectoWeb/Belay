# Submitting Belay to the Mac App Store, step by step

Everything on the code side is done. What is left is an hour in two of Apple's
web interfaces and one archive out of Xcode. Written on 2026-08-13, after the
direct channel shipped as v1.0.0.

The neighbouring project `/Volumes/BASE/Work/Apps/iOS/f64` went through the
same account, team `VSY2EB4Y9E`, with automatic signing, and this follows the
path that worked there.

**Correcting earlier advice in this repository:** you do not need to make a Mac
App Distribution certificate, a Mac Installer Distribution certificate or an
App ID by hand. `Belay-MAS` is on automatic signing, so Xcode creates all three
the first time you archive. `docs/APP-STORE.md` and `BLOCKERS.md` were written
before that was set up and asked for the manual route.

---

## Step 1. Check Xcode is signed in

Xcode, Settings, Accounts. The Apple ID that owns team `VSY2EB4Y9E` should be
listed. It already is if f/64 was shipped from this Mac.

## Step 2. Archive the App Store build

```
open Belay.xcodeproj
```

Scheme: **Belay-MAS**. Destination: **My Mac**. Then Product, Archive.

The first archive is where Xcode registers the App ID `com.perfectoweb.belay`,
issues an Apple Distribution certificate and creates the provisioning profile.
If it asks to do any of that, say yes.

Watch for one thing: the scheme must be `Belay-MAS` and not `Belay`. The direct
build has no sandbox and would be rejected on upload.

### Check the archive before you go any further

An archive can look perfectly normal in the Organizer and be useless. Run this
against it, replacing the path with the archive you just made:

```
codesign -dv --verbose=2 ~/Library/Developer/Xcode/Archives/*/Belay-MAS*.xcarchive/Products/Applications/Belay.app
```

Two lines matter. `Identifier=com.perfectoweb.belay`, not `Identifier=Belay`,
and `TeamIdentifier=VSY2EB4Y9E`, not `not set`. If you see `Signature=adhoc`
the app was not signed at all, and nothing downstream will tell you so.

Then check the sandbox is really in there:

```
codesign -d --entitlements :- ~/Library/Developer/Xcode/Archives/*/Belay-MAS*.xcarchive/Products/Applications/Belay.app | grep app-sandbox
```

One line of output is right. Silence means the archive is the wrong build, and
uploading it wastes a review cycle.

The first archive made on this Mac failed both checks, because the target was
briefly configured with an empty signing identity. Xcode reported nothing.

## Step 3. Create the app record

<https://appstoreconnect.apple.com>, Apps, "+", New App.

| Field | Value |
|---|---|
| Platform | macOS |
| Name | `Belay - Awake for AI Agents` (or the alternative in APP-STORE-LISTING.md) |
| Primary language | English (U.S.) |
| Bundle ID | `com.perfectoweb.belay`, in the list once step 2 has run |
| SKU | `belay-mac-1` |
| Access | Full Access |

Plain `Belay` is taken on this store, which is why the name carries a
description.

## Step 4. Upload the build

Xcode, Window, Organizer, Archives, the archive from step 2, Distribute App,
App Store Connect, Upload. Defaults the whole way.

Processing on Apple's side takes 15 to 40 minutes. An email says when it is
ready.

## Step 5. Fill in the listing

Everything to paste is in `docs/APP-STORE-LISTING.md`, in six languages, each
field already counted against Apple's limit. The parts that are not text:

- **Screenshots.** `Promo/AppStore/belay-en-appstore-1.png` through `-6.png`,
  2880 by 1800, alpha already stripped because App Store Connect rejects
  screenshots that have it.
- **Category.** Developer Tools, secondary Utilities.
- **Age rating.** 4+, no questions answered yes.
- **Price.** Free.
- **Privacy policy URL.** `https://perfectoweb.github.io/Belay/privacy/`
  The capital B matters; the lowercase spelling is a 404.
- **Support URL.** `https://github.com/PerfectoWeb/Belay/issues`

## Step 6. App Privacy

Answer **Data Not Collected**. Nothing in the app collects anything, the App
Store build has no outbound network entitlement, and the privacy page says the
same thing in the same words.

## Step 7. Encryption

`ITSAppUsesNonExemptEncryption` is already `false` in `project.yml`, so App
Store Connect will not ask.

## Step 8. Notes for review, and this one matters

> **2026-08-16.** The notes were rewritten again after the second rejection and
> no longer describe a listener, because there is not one in this build. The
> current text is `docs/app-review-notes.txt`, and the reply that goes with it
> is `docs/app-review-reply.txt`.
>
> The key in `.secrets/` can read this field but not write it: `PATCH` returns
> 403 FORBIDDEN_ERROR, "the API key in use does not allow this request".
> Writing it needs a second key with the App Manager role, so the notes are
> pasted in by hand and `app-review-notes.txt` is kept as the copy of what is
> actually there.

Paste `docs/app-review-notes.txt` into **App Review Information → Notes**. It is
written to be true of the build that is actually uploaded, which is a rule this
project learned the hard way twice: an early draft said the listener was "off
until the user turns it on", which is not what the code did, and the version
after that defended an entitlement for a feature that could not work in a
sandbox. See "The 2.4.5 rejection, twice" below.

The block that used to sit here was the old notes text, arguing for a listener
this build no longer has. It is in the git history if the argument is ever
wanted again; keeping a stale copy of a review answer beside the live one is how
the wrong one gets pasted.

### The 2.4.5 rejection, twice, and how it was actually resolved

The first reply to this argued that the listener was real, that the automated
scan had missed it because Swift's `NWListener` overlay does not use the C entry
points, and that `network.client` is not a substitute because the sandbox
distinguishes `connect(2)` from `bind(2)`. Every one of those statements is
true, and the whole argument was beside the point.

App Review asked again on 2026-08-16. This time the feature was checked rather
than the argument, and the feature does not work in this build:
`HookInstaller` writes into `~/.claude/settings.json`, which it derives from
`FileManager.default.homeDirectoryForCurrentUser`, and inside the App Sandbox
that is the app's own container. Pressing "Enable" in the App Store build would
have written a hook file into `~/Library/Containers/com.perfectoweb.belay/Data/.claude/`
and reported success. Claude Code has never read that path.

So the entitlement was supporting a feature with no working functionality behind
it, which is exactly what guideline 2.4.5 says. It was removed the same day,
along with the listener and the control that offered it:

- `Belay-MAS.entitlements` now holds three keys and no network entitlement in
  either direction.
- `PreciseDetection.isSupported` is false under `BELAY_MAS`; `start()` returns
  before binding, and `ProvidersSettingsPane` does not draw the row.
- `verify-mas-build.sh` fails if either network entitlement reappears, and
  `ChannelSurfaceTests` fails if the code and the entitlements file disagree
  about which build this is.

The transcript watcher is unaffected. It reaches the real `~/.claude` through
the security-scoped bookmark the user grants, which is why detection works in
that build and the installer never did.

**The lesson worth keeping.** Two rounds were spent defending an entitlement
instead of testing the feature it was for. When a reviewer says an entitlement
has no matching functionality, run the feature in the sandboxed build before
writing a word of reply.

**Do not upload a bundle built by the test scheme.** The Debug MAS product in
`build/DerivedData-MAS` carries Xcode's test-host injections — a
`temporary-exception.files.absolute-path.read-only` for `/` and three
`mach-lookup` exceptions — which is precisely the "more than the minimum set of
entitlements" the same guideline is about. Only ever ship the archive export;
`Belay-MAS.entitlements` itself is clean and `SandboxAccessTests` asserts it.

## Step 9. Submit

Add the build to the version, then Submit for Review.

---

## Not needed, deliberately

**The Paid Apps agreement.** The tip jar is compiled but not reachable from the
app, so there is nothing to sell and no In-App Purchase to create. `BLOCKERS.md`
B2 is the record of that decision. f/64 needed this; Belay does not.

**TestFlight.** Worth it if you want a day on the Release build first. Nothing
in the submission depends on it.

## Known risks, in the order a reviewer would find them

1. **The loopback listener.** Covered by step 8.
2. **Writing to another app's settings file.** Consent-gated, backed up,
   reversible from the same screen. Step 8 says so.
3. **macOS 14 and 15 are not tested.** The app declares 14.0 and has only ever
   run on 26.4. If a reviewer is on 14, this is where it would go wrong.
   `BLOCKERS.md` B5.
4. **Translations have had no native review** beyond English and Russian.
   `BLOCKERS.md` B7.

---

## After a release goes out

`scripts/bump-cask.sh` points the Homebrew cask at the new version. It is not
part of `release.sh` on purpose: the cask can only be moved once the asset is
downloadable, which is after the GitHub Release exists, and a release script
that half-fails leaves a tap pointing at a file nobody can fetch.
