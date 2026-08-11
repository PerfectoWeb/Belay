# 06 — Distribution

## Two channels, one codebase

| | **Direct** (Developer ID + notarized) | **Mac App Store** |
|---|---|---|
| Sandbox | off | required |
| Updates | Sparkle 2 (EdDSA-signed appcast) | App Store |
| Monetisation | "Buy me a coffee" link | StoreKit 2 consumable tips |
| Hook installation | direct filesystem write | user-granted, bookmark-scoped |
| Risk | none | review friction (see below) |

Two XcodeGen schemes, `Vigil` and `Vigil-MAS`, differing by compile condition
`VIGIL_MAS` and entitlements file. **Do not fork the source.** Isolate the
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
com.apple.security.network.server                     true   # only if HTTP hook bridge ships
```

No `network.client` in the MAS build — there is nothing to phone home to, and
its absence is a selling point.

**Security-scoped bookmarks.** Store the `~/.claude` bookmark in
`UserDefaults`, resolve on launch, and handle the stale case (bookmark
`isStale` → silently re-resolve, or prompt once). Always balance
`startAccessingSecurityScopedResource()` with a `defer` stop. Leaking these
eventually exhausts a per-process limit and detection dies with no obvious cause.

This is now built. Where it lives:

| | |
|---|---|
| `VigilSupport/BookmarkFileAccess.swift` | the sandboxed `FileAccessProvider` |
| `VigilSupport/SecurityScopedBookmarks.swift` | Foundation's four calls, behind a protocol so the balance is testable |
| `VigilSupport/BookmarkStore.swift` | the bytes, in `UserDefaults` under `VigilClaudeFolderBookmark` |
| `VigilApp/Onboarding/ClaudeFolderPanel.swift` | the `NSOpenPanel` grant |
| `VigilApp/Onboarding/ClaudeAccess.swift` | which implementation this channel gets |

Four details that are not obvious and are load-bearing:

- **The home is not the container.** `NSHomeDirectory()` and
  `FileManager.homeDirectoryForCurrentUser` both answer with the sandbox
  container, so a MAS build looking for `~/.claude` finds its own empty
  container. `VigilSupport.UserHome.real` reads the account record instead.
- **One standing scope, plus the brackets.** `withAccess` opens and closes a
  scope around each read, which is what keeps the count balanced. It is not
  enough on its own: FSEvents watches the granted directory continuously and
  `FileSnapshot`'s stats happen outside any bracket, so `BookmarkFileAccess`
  also holds exactly one scope on the granted root for as long as it lives, and
  releases it in `VigilController.shutdown`.
- **A stale bookmark is renewed, never dropped.** It still resolves; Foundation
  only wants it re-encoded. Discarding it would send the user back through the
  panel for a housekeeping detail, and a failed renewal keeps the bytes that
  still work.
- **The choice is made in the app.** `#if VIGIL_MAS` does not reach a local
  SwiftPM target (`PROJECT_STATE.md` D15), so `ClaudeAccess` picks the
  implementation and `VigilController` injects it into `ProviderHost`. Nothing
  in detection can tell which it got.

> **What is still unproved.** None of this has run inside a real sandbox: a test
> process cannot create a scoped bookmark, so the suites cover the logic around
> Foundation's calls rather than the calls. `BLOCKERS.md` B8 lists exactly what
> one signed, provisioned run on a real machine has to confirm — including the
> reads VigilProviders performs outside `withAccess`, and the generic provider's
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

Provide a **demo video** and a scripted walkthrough — a reviewer without Claude
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
  the MAS build — Apple rejects third-party updaters. Verify by grepping the
  built MAS binary for Sparkle symbols in CI.

## Monetisation

The plan is free with optional support. Concretely:

- **MAS:** StoreKit 2 **consumable** IAP tips (e.g. Small/Medium/Large Coffee).
  Apple requires in-app purchase for digital tipping; a PayPal/Ko-fi link inside
  a MAS build is a guideline violation and will be rejected. Implement in a
  `VigilTipJar` module with a clean `TipJarProviding` protocol; the direct build
  supplies a link-based implementation of the same protocol.
- **Direct:** a plain "Support development" link. No nag screens, no timed
  prompts, no feature gating. The tip UI lives in About and nowhere else.

Register the IAP product IDs yourself is **not** possible without the user's App
Store Connect account — implement against placeholder IDs defined in one
constants file, gate the UI behind a feature flag that's off until products
exist, and note it in `BLOCKERS.md`.

## Signing & packaging

- Local dev: ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`) so `scripts/build-local.sh`
  produces a runnable `.app` with no developer account. This is what you'll use
  for the whole build.
- `scripts/release.sh` (written, not run): archive, export with Developer ID,
  `notarytool submit --wait`, `stapler staple`, produce a DMG via
  `create-dmg`. Leave the team ID as a clearly-marked placeholder.
- Hardened Runtime on for the direct build. No `disable-library-validation`
  unless something concretely requires it — it isn't likely to here.

## Bundle metadata

```
LSUIElement                     true      # menu bar only, no Dock icon
LSMinimumSystemVersion          14.0
NSHumanReadableCopyright        …
ITSAppUsesNonExemptEncryption   false
```

No usage-description strings are needed for what we do; if you find yourself
adding one, question whether the feature belongs in v1.0.
