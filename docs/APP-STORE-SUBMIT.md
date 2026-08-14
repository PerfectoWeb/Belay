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

> **2026-08-14, still outstanding.** The notes field in App Store Connect holds
> the *old* text, the one that says Precise Detection "is off by default" and
> that Belay "listens only when enabled by the user". That is not what the code
> does — the listener starts in `applicationDidFinishLaunching` and runs for the
> lifetime of the app — and it is the worst possible thing to have said in a
> 2.4.5 dispute, because it tells the reviewer the functionality is switched
> off. The replacement is `docs/app-review-notes.txt`; paste it into App Review
> Information by hand. The App Store Connect API key in `.secrets/` can read
> that field but not write it: `PATCH` returns 403 FORBIDDEN_ERROR, "the API key
> in use does not allow this request".

Belay opens a listening socket on `127.0.0.1`, and the 1.0.0 submission was
rejected over it — not by a reviewer, by an automated check. Guideline 2.4.5,
"includes the com.apple.security.network.server entitlement but does not appear
to have matching functionality". See "The 2.4.5 rejection" below for why the
check is wrong and what to send back.

Paste this into **App Review Information → Notes**. It is written to be true of
the build that is actually uploaded; the earlier draft of this section said the
listener was "off until the user turns it on", which is not what the code does,
and telling App Review that would have been worse than the rejection.

> Belay is a menu bar utility that keeps the Mac awake while a local AI coding
> agent is working. It has no account, no server and no analytics.
>
> **Why the app needs com.apple.security.network.server.** Belay runs an HTTP
> listener bound to 127.0.0.1 so that Claude Code — a command line tool running
> on the same Mac, outside our sandbox — can post lifecycle events to it
> ("a run started", "a run finished", "the agent is waiting for input"). This is
> what makes detection immediate instead of inferred. The listener is created
> with NWListener from Network.framework, on an ephemeral port, bound to the
> loopback interface only, and every request must carry a bearer token that
> Belay writes to its own container. It accepts no connection from outside the
> machine and initiates none: this build deliberately ships **without**
> com.apple.security.network.client and therefore cannot make an outbound
> connection at all.
>
> The listener starts with the app, so it is running the moment the app is
> launched and needs no setup to observe. Installing the matching hook entry in
> Claude Code's own settings file is separate, is off by default, and happens
> only from a button that shows the exact text of the change first; the same
> screen removes it.
>
> **To see it working, in about a minute and with no account:**
>
> 1. Launch Belay. The listener is already up:
>    `lsof -nP -iTCP -sTCP:LISTEN -a -c Belay` prints a line ending
>    `TCP 127.0.0.1:<port> (LISTEN)`.
> 2. The same port and its token are in
>    `~/Library/Containers/com.perfectoweb.belay/Data/Library/Application Support/Belay/bridge.json`.
> 3. Post to it the way Claude Code does:
>    `curl -i -X POST -H "Authorization: Bearer <token>" "http://127.0.0.1:<port>/hook?state=working"`
>    It answers **204**. Without the header, or with a wrong token, it answers
>    **401** and reads nothing.
> 4. Belay's panel now shows a session working and the Mac is being held awake;
>    `pmset -g assertions | grep Belay` shows the assertion macOS granted.
>
> Note that Belay does not add its hook to Claude Code's settings file unless
> the user asks it to, in **Settings ▸ Providers ▸ Precise detection**, from a
> button that shows the exact change first. So on a fresh install the socket is
> listening and idle: it is waiting for an agent that has not been pointed at it
> yet. Step 3 above is exactly what that agent would send.
>
> No sign-in is required to review any part of the app.

### The 2.4.5 rejection, and why the automated check missed it

The functionality is in the binary. In the 1.0.0 archive:

```
otool -L .../Belay.app/Contents/MacOS/Belay | grep Network
    /System/Library/Frameworks/Network.framework/Versions/A/Network

nm -u .../Belay.app/Contents/MacOS/Belay | grep NWListener
    _$s7Network10NWListenerC18stateUpdateHandleryAC5StateOcSgvs
    _$s7Network10NWListenerC20newConnectionHandleryAA12NWConnectionCcSgvs
    _$s7Network10NWListenerC4portAA10NWEndpointO4PortVSgvg
    ...
```

The likely reason the check did not see it: those are Swift symbols. A Swift app
using `NWListener` never references the C entry points (`nw_listener_create`,
`bind`, `listen`) directly — the Swift overlay does, inside
`libswiftNetwork.dylib`. A scanner looking for the C symbols in the app binary
finds nothing.

And the entitlement is not merely used, it is **required**: `network.client` is
not a substitute, because the sandbox distinguishes by direction. The same
`NWParameters` Belay uses were compiled into a standalone probe and run three
ways, ad-hoc signed:

| Sandbox | Entitlements | Result |
|---|---|---|
| off | — | `READY port=59439` |
| on | `network.client` only | **`FAILED POSIXErrorCode(1): Operation not permitted`** |
| on | `network.server` | `READY port=59441` |

`client` authorises the outbound `connect(2)`; `NWListener` performs `bind(2)`
and `listen(2)`, which the sandbox refuses with EPERM without `network.server`,
loopback included. Without it Belay loses exact detection entirely in this
channel.

There is no build change that fixes this honestly, and no entitlement to drop:
the four in `Belay-MAS.entitlements` each have a named consumer in the code, and
the direct build declares none at all.

So: reply to the message, put the same explanation in App Review Information,
and resubmit. Reply text, ready to paste:

> The com.apple.security.network.server entitlement is required and is used at
> every launch.
>
> Belay keeps a Mac awake while a local AI coding agent is working. To know when
> a run starts and stops it accepts events from Claude Code, a command line tool
> running on the same Mac and outside our sandbox. It receives them over an HTTP
> listener created with NWListener (Network.framework), bound to 127.0.0.1 on an
> ephemeral port, restricted to the loopback interface, and protected by a
> bearer token written to the app's own container. The listener starts in
> applicationDidFinishLaunching and runs for the lifetime of the app.
>
> The app cannot make outbound connections: it deliberately ships without
> com.apple.security.network.client, which is also why network.client is not an
> alternative here. The sandbox distinguishes by direction — client authorises
> connect(2), while NWListener performs bind(2) and listen(2), which the sandbox
> denies with EPERM without network.server even on the loopback address. We
> verified this with a standalone probe using the same NWParameters: sandboxed
> with network.client only it fails with "Operation not permitted"; with
> network.server it binds.
>
> The listener may appear idle on a fresh install, which we think is why the
> automated analysis did not match it to functionality. Nothing posts to it
> until the user enables the integration in Settings > Providers > Precise
> detection. To exercise it directly:
>
>   lsof -nP -iTCP -sTCP:LISTEN -a -c Belay
>   cat ~/Library/Containers/com.perfectoweb.belay/Data/Library/Application\ Support/Belay/bridge.json
>   curl -i -X POST -H "Authorization: Bearer <token>" "http://127.0.0.1:<port>/hook?state=working"
>
> The third command returns 204 and the app's panel immediately shows a working
> session; the same request without the token returns 401. No account or sign-in
> is needed for any of this.
>
> We would also note that the app binary references NWListener through Swift's
> Network overlay rather than the C entry points (nw_listener_create, bind,
> listen), which a symbol-level scan of the app binary would not find. The
> symbols are present as _$s7Network10NWListenerC... in the submitted build.

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
