# 06 – Distribution

## Two channels, one codebase

| | **Direct** (Developer ID + notarized) | **Mac App Store** |
|---|---|---|
| Sandbox | off | required |
| Updates | A daily check against the GitHub releases API (`ReleaseChecker`). Sparkle is written but commented out of `project.yml` and ships in neither channel. | App Store |
| Monetisation | A Donate link. `coffeeURL` is permanently nil. | Nothing. Tips need a paid-apps agreement this account cannot sign, so the StoreKit code was deleted rather than kept unused. |
| Hook installation | direct filesystem write | user-granted, bookmark-scoped |
| Risk | none | review friction (see below) |

Two XcodeGen schemes, `Belay` and `Belay-MAS`, differing by compile condition
`BELAY_MAS` and entitlements file. **Do not fork the source.** Isolate the
differences behind two protocols:

```swift
protocol FileAccessProvider {          // plain FileManager vs security-scoped bookmarks
    func hasAccess(to url: URL) -> Bool
    func withAccess<T>(to url: URL, _ body: (URL) throws -> T) throws -> T
}

protocol UpdateChannel {               // Sparkle vs no-op
    var isSupported: Bool { get }
    func checkForUpdates()
}
```

Ship direct first. It's the build you can release this month, it validates the
product, and it has no review risk. Submit to the App Store after.

## App Sandbox entitlements (MAS build)

```
com.apple.security.app-sandbox                        true
com.apple.security.files.user-selected.read-write     true
com.apple.security.files.bookmarks.app-scope          true
```

Three, and no network entitlement in either direction.

`network.server` was here until 2026-08-16, for the hook bridge. App Review
asked about it twice under guideline 2.4.5 and the answer, once we looked
properly, was that they were right: `HookInstaller` writes into
`~/.claude/settings.json`, and inside the sandbox the home directory is the
container, so the feature could never have worked in this build. The listener is
off here, the control is hidden, and `verify-mas-build.sh` fails if either comes
back. Detection in this build is the transcript watcher, which needs no network.

`network.client` has never been present. There is nothing to phone home to, and
its absence is a selling point.

**Security-scoped bookmarks.** Store the `~/.claude` bookmark in
`UserDefaults`, resolve on launch, and handle the stale case (bookmark
`isStale` → silently re-resolve, or prompt once). Always balance
`startAccessingSecurityScopedResource()` with a `defer` stop. Leaking these
eventually exhausts a per-process limit and detection dies with no obvious cause.

This is now built. Where it lives:

| | |
|---|---|
| `BelaySupport/BookmarkFileAccess.swift` | the sandboxed `FileAccessProvider` |
| `BelaySupport/SecurityScopedBookmarks.swift` | Foundation's four calls, behind a protocol so the balance is testable |
| `BelaySupport/BookmarkStore.swift` | the bytes, in `UserDefaults` under `BelayClaudeFolderBookmark` |
| `BelayApp/Onboarding/ClaudeFolderPanel.swift` | the `NSOpenPanel` grant |
| `BelayApp/Onboarding/ClaudeAccess.swift` | which implementation this channel gets |

Four details that are not obvious and are load-bearing:

- **The home is not the container.** `NSHomeDirectory()` and
  `FileManager.homeDirectoryForCurrentUser` both answer with the sandbox
  container, so a MAS build looking for `~/.claude` finds its own empty
  container. `BelaySupport.UserHome.real` reads the account record instead.
- **One standing scope, plus the brackets.** `withAccess` opens and closes a
  scope around each read, which is what keeps the count balanced. It is not
  enough on its own: FSEvents watches the granted directory continuously and
  `FileSnapshot`'s stats happen outside any bracket, so `BookmarkFileAccess`
  also holds exactly one scope on the granted root for as long as it lives, and
  releases it in `BelayController.shutdown`.
- **A stale bookmark is renewed, never dropped.** It still resolves; Foundation
  only wants it re-encoded. Discarding it would send the user back through the
  panel for a housekeeping detail, and a failed renewal keeps the bytes that
  still work.
- **The choice is made in the app.** `#if BELAY_MAS` does not reach a local
  SwiftPM target (`PROJECT_STATE.md (git history)` D15), so `ClaudeAccess` picks the
  implementation and `BelayController` injects it into `ProviderHost`. Nothing
  in detection can tell which it got.

> **What is still unproved.** None of this has run inside a real sandbox: a test
> process cannot create a scoped bookmark, so the suites cover the logic around
> Foundation's calls rather than the calls. `BLOCKERS.md (git history)` B8 lists exactly what
> one signed, provisioned run on a real machine has to confirm – including the
> reads BelayProviders performs outside `withAccess`, and the generic provider's
> folders, which are outside the `~/.claude` grant entirely.

## App Review: expect friction, prepare for it

Two things a reviewer will question. Write the answers into the review notes
*before* submitting:

1. **Reading another app's configuration directory.** Explain: user explicitly
   grants access via a standard open panel; only structural metadata is read;
   nothing is transmitted; there is a functional mode without it.
2. **A loopback listening socket.** Explain: 127.0.0.1 only, token-authenticated,
   used solely to receive local lifecycle events; no outbound network access at
   all (point at the missing `network.client` entitlement as proof).

Provide a **demo video** and a scripted walkthrough – a reviewer without Claude
Code installed cannot exercise the core feature. Include a hidden-ish "Demo
mode" that simulates a session so the reviewer can see the whole flow. That
single addition is often the difference between approval and a rejection loop.

Fallback plan if the socket is rejected: ship MAS with Tier A + the command-shim
bridge only, and keep the HTTP receiver in the direct build behind the compile
flag. Design for this from the start so it's a one-line change, not a refactor.

## Sparkle (direct build only)

- Sparkle 2 via SPM, `SUFeedURL` pointing at an appcast hosted on GitHub Pages
  or the releases bucket, **HTTPS only**.
- EdDSA signing. The private key goes in the user's Keychain, never in the repo.
  Add `scripts/sign-update.sh` wrapping `generate_appcast`.
- Default to **check** automatically, **do not install** automatically. Users of
  a system utility deserve to choose when it restarts.
- The entire Sparkle dependency, its entitlements and its UI must be absent from
  the MAS build – Apple rejects third-party updaters. Verify by grepping the
  built MAS binary for Sparkle symbols in CI.

## Monetisation

Free, with a Donate link in the direct build and nothing at all in the App Store
build. That is the whole of it.

The original plan had StoreKit 2 consumable tips in the App Store build, behind
a `TipJarProviding` protocol so the direct build could supply a link-based
implementation of the same thing. Both were written and tested. Neither was ever
called: tips need a paid-apps agreement this account cannot sign, so no products
could be registered and there was nothing to sell.

The code was deleted on 2026-08-16 rather than left as a seam nobody walks
through. `BLOCKERS.md (git history)` B2 records the account decision, and the git history
records the implementation, which is the right place for both. If tips ever
become possible, that history is a better starting point than an untested module
that has been rotting in the build.

## Signing & packaging

- Local dev: ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`) so `scripts/build-local.sh`
  produces a runnable `.app` with no developer account. This is what you'll use
  for the whole build.
- `scripts/release.sh` (run for real on 2026-08-13 and 2026-08-14): archive, export with Developer ID,
  `notarytool submit --wait`, `stapler staple`, produce a DMG via
  `create-dmg`. Leave the team ID as a clearly-marked placeholder.
- Hardened Runtime on for the direct build. No `disable-library-validation`
  unless something concretely requires it – it isn't likely to here.

## Bundle metadata

```
LSUIElement                     true      # menu bar only, no Dock icon
LSMinimumSystemVersion          14.0
NSHumanReadableCopyright        …
ITSAppUsesNonExemptEncryption   false
```

No usage-description strings are needed for what we do; if you find yourself
adding one, question whether the feature belongs in v1.0.
