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

The first archive is where Xcode registers the App ID `com.perfecto-web.belay`,
issues an Apple Distribution certificate and creates the provisioning profile.
If it asks to do any of that, say yes.

Watch for one thing: the scheme must be `Belay-MAS` and not `Belay`. The direct
build has no sandbox and would be rejected on upload.

## Step 3. Create the app record

<https://appstoreconnect.apple.com>, Apps, "+", New App.

| Field | Value |
|---|---|
| Platform | macOS |
| Name | `Belay - Awake for AI Agents` (or the alternative in APP-STORE-LISTING.md) |
| Primary language | English (U.S.) |
| Bundle ID | `com.perfecto-web.belay`, in the list once step 2 has run |
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

Belay opens a listening socket on `127.0.0.1`. A reviewer who notices will ask,
and answering before they ask is cheaper than a rejection. Paste something like:

> Belay is a menu bar utility that keeps the Mac awake while a local AI coding
> agent is working. It has no account, no server and no analytics.
>
> The app opens a loopback listener on 127.0.0.1 so Claude Code, which runs on
> the same Mac, can tell it when a run starts and stops. The listener is bound
> to the loopback interface and requires a bearer token stored in the user's
> own Application Support directory. This build ships without the
> com.apple.security.network.client entitlement, so it cannot make outbound
> connections at all. The feature is off until the user turns it on.
>
> With the user's explicit confirmation, and only from a button that shows the
> exact text first, Belay adds one hook entry to Claude Code's own settings
> file. The same screen removes it.
>
> No sign-in is required to review any part of the app.

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
