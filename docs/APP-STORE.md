# App Store

The concrete path from what is in this repository to a Mac App Store listing.

`docs/06-DISTRIBUTION.md` describes the two-channel design and
[`adr/004-mas-and-direct-split.md`](adr/004-mas-and-direct-split.md) records why
it is one codebase. This file is the operational half: what Apple will ask for
that does not exist yet, what a reviewer will see, and the order the work has to
happen in.

Read [`BLOCKERS.md`](BLOCKERS.md) first. Nothing here contradicts it.

---

## Status, plainly

The `Belay-MAS` scheme builds. It is sandboxed, it carries exactly the four
entitlements `docs/06` specifies, it has no `com.apple.security.network.client`,
and [`../scripts/verify-mas-build.sh`](../scripts/verify-mas-build.sh) proves all
of that plus the absence of Sparkle. That is real and it is done.

None of it has been submitted, uploaded, validated, or seen by Apple. No app
record exists. No bundle identifier has been registered in the Developer portal.
No screenshots exist anywhere in this repository.

## Blocker zero — CLOSED (2026-08-12)

This page used to open with a long section saying the sandboxed build could not
read `~/.claude`, that nothing in the tree resolved a security-scoped bookmark,
and that the one `NSOpenPanel` belonged to the generic provider. All of that was
true when it was written and none of it is true now. It is `BLOCKERS.md` B8, and
B8 is resolved: the grant flow was built, run by hand inside the real container,
and a 660-byte `BelayClaudeFolderBookmark` came back.

What exists now, so nobody has to grep for it again:

| Piece | Where |
|---|---|
| Bookmark create / resolve / start-stop accessing | `Packages/BelayKit/Sources/BelaySupport/SecurityScopedBookmarks.swift` |
| The file access implementation that uses it | `Packages/BelayKit/Sources/BelaySupport/BookmarkFileAccess.swift` |
| The one-time grant panel for `~/.claude` | `Sources/BelayApp/Onboarding/ClaudeFolderPanel.swift` |
| Which implementation each channel gets | `Sources/BelayApp/Onboarding/ClaudeAccess.swift` |
| Tests that run inside a container | `Tests/BelaySandboxTests/` |

The section is kept as a heading rather than deleted because the old text was
quoted into other documents and into `PROJECT_STATE.md`, and a reader who
follows one of those links deserves to land on the correction rather than on
nothing.

## What Apple will ask for that does not exist yet

### Apple Developer Program membership and role

Team ID `VSY2EB4Y9E` is present and has a Developer ID Application certificate
(`BLOCKERS.md` B1), so the program membership exists. App Store distribution
additionally needs the account to be able to create app records in App Store
Connect. Confirm the role before starting; an account that can sign a Developer
ID build cannot necessarily create a listing.

### Bundle identifier registration

`com.perfectoweb.belay`, set in [`../project.yml`](../project.yml). It has never
been registered as an explicit App ID in the Developer portal, and the App
Sandbox capability has to be enabled on it there before a Mac App Store
provisioning profile can be issued.

One open question, not a decision this document should make: `docs/NAMING.md`
says both channels use the same bundle identifier. That is legal, but it means a
user who has the direct build installed and then installs the App Store build
ends up with two bundles claiming one identifier, one `UserDefaults` suite, and
one `~/Library/Application Support/Belay` directory holding one `bridge.json`.
Decide deliberately whether the MAS build gets its own suffix before the
identifier is registered, because changing it afterwards means a new app record.

### Category

`LSApplicationCategoryType` is **present** in
[`../Sources/BelayApp/Info-MAS.plist`](../Sources/BelayApp/Info-MAS.plist), set from
`project.yml`, and its value is:

```
LSApplicationCategoryType   public.app-category.developer-tools
```

App Store Connect's category must be set to match it. Developer Tools is the
right answer for a thing whose whole audience is people running coding agents;
this page previously advised Utilities, which would have disagreed with the
shipped plist.

Primary category in App Store Connect: Utilities. Secondary: Developer Tools is
the honest second choice, since the entire audience is people running coding
agents. Both are set in App Store Connect as well as in the plist; they have to
agree.

### Age rating

Fill in the questionnaire with "None" for every content question. There is no
user-generated content, no web view, no browser, no gambling, no purchases of
physical goods. The answer to unrestricted web access is No. The result is 4+.

### Privacy nutrition labels

The App Privacy section of App Store Connect. The answers for the MAS build:

- **"Do you or your third-party partners collect any data from this app?"** →
  **No.**
- That answer closes the questionnaire and the listing shows **Data Not
  Collected**.

That answer is truthful and checkable, not a convenience. Justification, kept
somewhere you can hand to Apple if asked:

- There is no analytics SDK, no crash reporter and no third-party SDK of any
  kind. The only external dependency the project has ever considered is Sparkle,
  and it is absent from this channel by construction.
- The MAS build has no `com.apple.security.network.client` entitlement, so it
  cannot make an outbound connection at all. See
  [`../Resources/Entitlements/Belay-MAS.entitlements`](../Resources/Entitlements/Belay-MAS.entitlements),
  where the absence is documented as deliberate.
- The update check that exists in the direct build is compiled out here
  (`ReleaseChecker.isSupported` is false under `BELAY_MAS`), and it was off by
  default anyway.
- Statistics are durations and counts in one local file, with no project names
  and no prompts in them. They leave the Mac only if the user shares a card
  themselves, through the system share sheet, which is a user action and not
  collection by the app.

Note the direct channel differs on exactly one point (an opt-in HTTPS GET to
`api.github.com` for the release check) and is not covered by these labels. Do
not copy this section into anything describing the direct build without that
sentence.

### Export compliance

`ITSAppUsesNonExemptEncryption` is already `false` in
[`../Sources/BelayApp/Info-MAS.plist`](../Sources/BelayApp/Info-MAS.plist), which is what
suppresses the export question on every upload. It is correct here, for reasons
worth writing down once:

- The MAS build makes no network connection, so it performs no TLS.
- The hook bridge's bearer token is generated with
  `SystemRandomNumberGenerator` and compared as a string. Random bytes are not
  encryption.
- There is no CryptoKit, no CommonCrypto, no custom or proprietary algorithm
  anywhere in the tree, and nothing encrypts data at rest beyond what the OS
  does for everyone.

The key is in `Info-Direct.plist` as well, so it also applies to the direct
build.
It remains correct there: that build's only network use is an HTTPS GET through
the system's own TLS, which is exempt. If a future version ever ships its own
cryptography, this key becomes a false statement to a government, not a
formality. Revisit it in the same commit.

### Screenshots

None exist. Required: at least one, up to ten, at one of the accepted macOS
sizes, and every screenshot in a set must be the same size:

```
1280 x 800
1440 x 900
2560 x 1600
2880 x 1800
```

2880 x 1800 is the sensible target on a Retina Mac. A menu bar app makes this
harder than usual, because there is no main window and a screenshot of the whole
desktop is mostly wallpaper. Plan on five:

1. The panel open under the menu bar, with two real sessions working.
2. The panel showing a safety rail having fired, with its plain-English reason.
3. Settings, Providers pane, showing the presets.
4. Settings, Behaviour pane, showing the caps and the battery guard.
5. The "an agent is waiting for you" notification.

Two warnings from this repository, both learned the hard way.
`docs/QA-CHECKLIST.md` records that `screencapture` photographs the whole screen
and once captured a personal chat on this machine. Use a windowed capture on a
clean user account with a plain wallpaper, or render the SwiftUI views to PNG
with `ImageRenderer`. Do not put a real project name in a screenshot; the panel
shows project folder names and that is somebody's directory tree.

### Support URL and privacy policy URL

Both are required fields and both must be publicly reachable without a login.
The repository is public now, so both exist.

- **Support URL.** `https://github.com/perfectoweb/belay/issues`. It is a
  legitimate support channel for a free project and Apple accepts it.
- **Privacy policy URL.** A GitHub issues page is not a privacy policy. Two
  workable options for a repo-only project:
  - **GitHub Pages.** Enable Pages on the repository and publish one page whose
    content is derived from [`SECURITY.md`](SECURITY.md), at a stable path
    such as `/privacy`. This is the better option: it is a real URL, it is
    versioned with the code, and it survives the repository being reorganised.
  - **A section of the README, linked by anchor.** Cheapest. It works, but the
    anchor breaks the first time a heading is renamed, and Apple will have
    recorded the broken link.

  A page on the domain behind `Branding.donateURL` is a third option if that
  domain is already maintained. Verify it resolves before using it; nothing in
  this repository proves it does.

  Whichever is chosen, the policy has to state what is collected (nothing), what
  is read locally, what is written locally, and how to contact the developer.
  `SECURITY.md` already contains all of that and is the source to derive from,
  not a substitute: it is written for engineers and reads like it.

### The remaining App Store Connect fields

Fields with no home in this repository, listed so none of them is a surprise on
submission day: app name as shown on the store, subtitle, promotional text,
description, keywords, marketing URL (optional), copyright line, and the review
contact's name, phone number and email address. The review contact is the
owner's own; it is not recorded here and should not be invented.

There is no sign-in anywhere in the app, so the demo account fields stay empty
and the review notes should say so explicitly.

### In-app purchase products

There are none, and there is no code for any. `BLOCKERS.md` B2: the developer
account cannot sign a paid-apps agreement, so no product could be registered.
The StoreKit tip jar that had been written against placeholder identifiers was
deleted on 2026-08-16.

The recommendation is to **submit v1.0 with the tip jar off**. Registering three
consumables means three more review items, tax and banking forms, and a StoreKit
surface that has never been exercised against a real product. A first submission
should have the smallest possible area. Turn it on in a later version, in the
same commit that registers the products, which is what the comment in that file
already tells you to do.

---

## Review risks specific to this app

For each: what a reviewer actually sees, and what the reply says. Put the short
form of all of them in the App Review Notes field before submitting, rather than
waiting to be asked. `docs/06` says this and it is right.

### 1. It reads another application's configuration directory

**What a reviewer sees.** An open panel on first run asking for `~/.claude`. If
they look at the sandbox container afterwards, an app-scoped bookmark to a
directory belonging to a different vendor's tool.

**Reply.** Access is granted by the user through a standard `NSOpenPanel` and by
no other means. Only structural fields are read: whether a transcript file grew
in bytes, and a record's `type` and `stop_reason`. Message content, prompts and
model output are never decoded into a value the app holds; there is a test that
sends a distinctive string in a prompt field and asserts it appears in no emitted
signal and no file the app writes. Nothing read is transmitted anywhere, and this
build has no entitlement that would let it transmit. The app has a functional
mode without the grant (Always on, which holds nothing that depends on reading
anything).

### 2. It writes to another application's settings file

**What a reviewer sees.** A button that modifies `~/.claude/settings.json`, a
file the app did not create. Guideline 2.4.5 has a sub-point about using the
appropriate APIs when modifying user data stored by other apps, and this is the
clearest case of it in the whole submission.

**Reply.** The write happens only from an explicit button press, never
automatically, never on launch, and never as a side effect of anything else. The
exact JSON that will be added is shown to the user before they press it. A
timestamped backup is taken first and the write is abandoned if the backup fails.
The write is atomic (temp file in the same directory, then `replaceItem`). If the
file is not plain JSON the app refuses to touch it and offers a snippet to paste
by hand instead. Every entry added is marked as the app's own, so uninstall is
exact and never removes a hook the user wrote. The whole feature is optional and
the app works without it.

This is invariant 6 in [`00-INVARIANTS.md`](00-INVARIANTS.md), so the behaviour is
a design rule rather than a promise made for review.

### 3. It used to run a loopback HTTP listener

**What a reviewer sees.** Nothing. There is no network entitlement in this build
and no listening socket.

**What happened.** The App Store build carried
`com.apple.security.network.server` for the hook bridge until 2026-08-16. App
Review queried it twice under guideline 2.4.5, and the second time we checked
the feature rather than the argument: `HookInstaller` edits
`~/.claude/settings.json`, and inside the sandbox `homeDirectoryForCurrentUser`
is the container, so enabling it would have written a hook file into a directory
Claude Code has never read. An entitlement supporting a feature with no working
functionality is exactly what 2.4.5 exists to catch.

`PreciseDetection.isSupported` is false in this build, so nothing binds and the
control is not offered, and
[`../scripts/verify-mas-build.sh`](../scripts/verify-mas-build.sh) fails the
build if either network entitlement reappears. Detection here is the transcript
watcher, which needs no network at all.

Point the reviewer at the verification commands in `SECURITY.md`; they take
fifteen seconds and answer the question better than prose does.

**Fallback if this is rejected anyway.** `docs/06` and `adr/004` both plan for it:
drop the hook bridge from the MAS build and keep it in the direct one. The
compile condition gates composition rather than being tangled through detection,
so it is meant to be a small change. It has never been tried. Budget a day, not
an hour, and expect the settings UI to need a hidden branch as well as the
receiver.

### 4. It holds a power assertion

**What a reviewer sees.** An entry in `pmset -g assertions` while an agent is
working. Possibly nothing at all, if they have no agent installed, which is the
more likely and more dangerous case (see the demo problem below).

**Reply.** One `PreventUserIdleSystemSleep` assertion at most, process-wide,
created with the public `IOPMAssertionCreateWithProperties`. Every assertion
carries a 120 second `kIOPMAssertionTimeoutKey` with
`kIOPMAssertionTimeoutActionRelease` and is re-armed at 75% of that lifetime
while work continues, so an app that crashes or is force-quit cannot leave the
Mac awake for more than the timeout window. The reason string is human-readable
and appears in `pmset` output, so the user can always see why. It is released on
idle, quit, `SIGTERM`, `SIGINT`, sleep, mode change, a battery guard trip and a
four-hour cap. The user's System Settings are never modified. No private API is
used.

### 5. A reviewer cannot exercise the app

**What a reviewer sees.** A menu bar icon. An empty panel. Nothing happens,
because they do not have Claude Code installed and signed in.

This is the risk most likely to cause a rejection, and it is worse than `docs/06`
anticipated, because the demo mode that document asked for was **built and then
removed**: it was reachable by accident from the menu and injected fake sessions
into a real user's panel (`PROJECT_STATE.md` D16). Removing it was right. It also
means the mitigation `docs/06` counted on does not exist.

**What to do, in preference order.**

1. Record a screen capture, two to three minutes, showing a real Claude Code run
   starting, the assertion appearing in `pmset -g assertions`, the run finishing,
   and the assertion disappearing. Host it somewhere Apple can reach and link it
   in the review notes. This is the single highest-value item on this page.
2. Give the reviewer a path they can drive themselves. Always on mode holds a
   real assertion with one click and no agent involved, so `pmset -g assertions`
   proves the app does what it claims within thirty seconds. Say so in the notes,
   in exactly those words, with the command spelled out.
3. If a demo mode is genuinely needed later, D16 already ruled on the shape: a
   build-time flag in a separate scheme, never a menu item a user can reach.

### 6. The tip jar seam with no products

**What a reviewer sees.** Nothing. There is no StoreKit code in the binary and
no product identifier anywhere in the bundle.

**Reply, and the check to run before submitting.** There is no purchase surface
to describe. This used to be a flag that had to be checked before every
submission; deleting the code removed the check along with it.

The failure to avoid is the opposite one: a **link-based** tip jar reaching the
App Store build. Soliciting tips through a Ko-fi or PayPal link inside a MAS app
is a guideline violation, not a grey area. The code already defends against this:
the channel is resolved at runtime from an `Info.plist` key, and an unlabelled
bundle resolves to `.appStore` deliberately, because guessing wrong that way
hides a button while guessing wrong the other way ships a violation
(`PROJECT_STATE.md` D15). Before submitting, confirm `BelayDistributionChannel`
in the built MAS `Info.plist` reads `appStore`, and confirm the About pane shows
no support link.

### 7. Sparkle

**What a reviewer sees.** Nothing, if the build is correct. A rejection for a
third-party updater, if it is not.

Already handled and already tested.
[`../scripts/verify-mas-build.sh`](../scripts/verify-mas-build.sh) scans every
Mach-O in the bundle for Sparkle load commands, symbols and strings, checks for
an embedded framework, and checks for `SUFeedURL` in the `Info.plist`. Sparkle is
also still commented out in `project.yml` entirely (`BLOCKERS.md` B3). Run the
script against the exact bundle that gets uploaded, not against a rebuild.

---

## The 2.4.5 and sandbox questions a menu bar utility draws

Guideline 2.4.5 collects the extra requirements for Mac App Store apps. The
sub-points that bite an `LSUIElement` background utility, by substance:

**Packaged with Apple's tooling, and no reading or writing outside the container
except as the sandbox permits.** This is blocker zero restated as a guideline.
Every path outside the container has to arrive through a user grant. There are
three: `~/.claude/projects`, `~/.claude/sessions`, and `~/.claude/settings.json`.
One grant on the parent directory covers all three, which is an argument for
asking for `~/.claude` rather than for each subdirectory.

**Self-contained, single app bundle, nothing installed into shared locations.**
Belay satisfies this today. It has no helper tool, no launch daemon, no
privileged component, and no `LaunchAgents` plist of its own. Launch at login
goes through `SMAppService.mainApp`, which registers the app itself. Keep it that
way: the moment a helper appears, this stops being free.

**No downloading or installing standalone code.** Nothing in Belay downloads
anything. The MAS build cannot. The presets that look like configuration are
configuration: array elements, not fetched content.

**Appropriate APIs when modifying data another app stores.** Review risk 2 above.
This is the one to write the longest note about.

**No auto-launching or background code without consent.** `launchAtLogin`
defaults to `false` in `SettingsValues`, it is a toggle the user has to find and
turn on, and it registers through `SMAppService` so macOS shows it in Login
Items and the user can revoke it there. The app spawns no process that outlives
it. Say all of that in the notes; a background utility that starts at login is
exactly what this clause exists to catch, and the honest answer clears it.

**No license screens, license keys or self-implemented copy protection.** Not
applicable. The app is free, and source-available under a licence that
forbids selling it.

Two more, outside 2.4.5:

**Guideline 4.2, minimum functionality.** A free single-purpose menu bar utility
is a plausible target for "this is more like a website or a simple utility". The
honest counter is not to argue: the app has a settings window with six panes, a
statistics view, notifications, three detection tiers, a configurable provider
system with presets, six localisations, and it does something the operating
system provides no way to do. State that in one sentence in the notes and move
on.

**Guideline 2.1, app completeness.** The reviewer must be able to see the app
work. See review risk 5. Everything else on this page is wasted if this one is
not handled.

---

## Checklist, in the order the work has to happen

Nothing below is dated, because several items depend on Apple and on work that
has not started.

**Before anything else**

- [ ] Decide whether the App Store channel is worth the work at all. The direct
      build reaches this audience today. Read `adr/004`'s "Direct only"
      alternative again before starting, because the honest cost of this list is
      weeks.
- [ ] Ship the direct channel first, completely, and learn from it. `docs/06` is
      unambiguous about the order and the reason.

**Make the sandboxed build actually work** (blocker zero, above)

- [x] Implement `BookmarkFileAccess`.
- [x] Build the one-time grant flow and the revoked/stale state.
- [x] Inject the right implementation per channel at composition.
- [x] Add the sandbox test matrix: FSEvents on a scoped resource, bookmark
      staleness across a restart, the `settings.json` write under the grant.
- [ ] Run the full detection suite under the `Belay-MAS` scheme, on a real
      machine, against a real Claude Code session. Not in a test host.
- [x] Record a new blocker entry for this in `BLOCKERS.md`. It is B8.

**Resolve the naming and identity questions**

- [ ] Do the App Store name-conflict search for "Belay" (`BLOCKERS.md` B4,
      `docs/NAMING.md`). Before the app record exists, not after.
- [ ] Decide whether the MAS build shares `com.perfectoweb.belay` or takes a
      distinct identifier, and write the decision down.
- [ ] Confirm the Apple Developer account role can create app records.
- [ ] Register the App ID with the App Sandbox capability enabled.

**Fix the bundle metadata**

- [x] `LSApplicationCategoryType` is set, to `public.app-category.developer-tools`.
      Match App Store Connect's category to it.
- [ ] Confirm `ITSAppUsesNonExemptEncryption` is still `false` and still true.
- [ ] Confirm `BelayDistributionChannel` reads `appStore` in the built MAS
      bundle.

**Build the publishing surface**

- [ ] Push the repository to `github.com/perfectoweb/belay` and make it public.
      Every URL below depends on this.
- [x] Publish the privacy policy (GitHub Pages preferred) and verify the URL
      loads in a private browser window.
- [ ] Verify the support URL loads.

**Produce the assets**

- [ ] Five screenshots at one consistent size, taken on a clean account with no
      real project names visible.
- [ ] The demo recording described in review risk 5.
- [ ] App name, subtitle, description, keywords, copyright line.

**Add the App Store release path**

- [ ] Write the MAS equivalent of
      [`../scripts/release.sh`](../scripts/release.sh). That script handles the
      direct channel only: Developer ID, notarize, staple, DMG. The App Store
      path is a different signing identity, a Mac App Store provisioning profile,
      an `app-store-connect` export and an upload. It does not exist.
- [ ] Run [`../scripts/verify-mas-build.sh`](../scripts/verify-mas-build.sh)
      against the exact archive being exported.

**Create the record and submit**

- [ ] Create the app record. Set both categories, the age rating, the URLs and
      the copyright line.
- [ ] Answer App Privacy: Data Not Collected.
- [ ] Leave the IAP products unregistered for v1.0. Keep `areRegistered` false.
- [ ] Write the review notes: the five replies above, in short form, plus the
      Always-on-plus-`pmset` walkthrough, plus "no sign-in, no demo account
      needed", plus a link to the recording.
- [ ] Upload, wait for the build to finish processing, and check for any
      entitlement or plist warning in the email that follows.
- [ ] Submit.

**Two things learned the hard way in August 2026, worth reading before the next
submission**

- **Test the feature before defending the entitlement.** Two review rounds were
  spent arguing that the listener was real and that `network.client` was not a
  substitute. Every word of that was true and all of it was beside the point: the
  feature behind the entitlement did not work in a sandboxed build at all. When a
  reviewer says an entitlement has no matching functionality, run the feature in
  the sandboxed build before writing a word of reply.
- **Never upload a bundle built by the test scheme.** The Debug MAS product in
  `build/DerivedData-MAS` carries Xcode's test-host injections: a
  `temporary-exception.files.absolute-path.read-only` for `/` and three
  `mach-lookup` exceptions. That is precisely the "more than the minimum set of
  entitlements" the same guideline is about. Ship the archive export and nothing
  else. `Belay-MAS.entitlements` itself is clean and `SandboxAccessTests` asserts
  it.

**After a rejection, if one comes**

- [ ] Reply in Resolution Center with the relevant note above rather than a
      rewrite. Most rejections here are questions, and a specific answer plus a
      command the reviewer can run resolves them faster than an appeal.
- [ ] If the loopback socket is the objection, execute the `docs/06` fallback:
      drop the bridge from the MAS build, keep it in the direct one, resubmit,
      and record what the reviewer actually said in `PROJECT_STATE.md`.
