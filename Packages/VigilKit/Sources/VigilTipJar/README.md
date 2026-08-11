# VigilTipJar

Optional support (tips) and the update channel — the two things that differ
between the direct build and the Mac App Store build.

Depends on `VigilSupport` only. No AppKit: `LinkTipJar` takes an injected
`@Sendable (URL) -> Void` opener rather than reaching for `NSWorkspace`, so the
package stays UI-free and the test can use a spy.

## The decision that would surprise a newcomer

**The channel is chosen at runtime, not with `#if VIGIL_MAS`.**

`docs/06` implies a compile-condition split, and that is what was tried first. A
`#warning` probe under Xcode 26.6 showed that `SWIFT_ACTIVE_COMPILATION_CONDITIONS`
set on an app target **does not reach a local SwiftPM target**. `#if VIGIL_MAS`
inside this package is therefore false in *every* build, including the App Store
one — `StoreKitTipJar` behind that gate would have been dead code everywhere and
impossible to test, which is the opposite of the safety property the split exists
to provide.

So both implementations compile, and `TipJar.forCurrentChannel(...)` picks one
from `DistributionChannel.current`, read from an `Info.plist` key each target
sets. An unlabelled bundle resolves to `.appStore`, deliberately: guessing wrong
in that direction hides a tip button, while guessing wrong the other way puts a
payment link inside a sandboxed App Store build, which is a guideline violation.

If the literal compile-condition gate is ever wanted, it is a `Package.swift`
change — a MAS-only product or a `.define` — not a change here.

## The other thing worth knowing

`TipProducts.areRegistered` is `false` and stays false until real StoreKit
product identifiers exist (`BLOCKERS.md` B2). While it is false,
`StoreKitTipJar.isAvailable` is false and `purchase` refuses **before** touching
StoreKit, so no system purchase sheet can appear against products that do not
exist. The tip UI stays hidden on the strength of that one flag.

`UpdateChannel` lives here rather than in a `VigilUpdates` target of its own for
the same boundary reason. `NoUpdateChannel` is what ships today; Sparkle is
deferred, and `project.yml` carries the commented block that enables it.
