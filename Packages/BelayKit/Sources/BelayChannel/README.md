# BelayChannel

Which build this is, and what that build is allowed to do.

One fact, read from the bundle rather than from a compile condition:
`BelayDistributionChannel` in `Info.plist`, set by `project.yml` per target.
Xcode does not pass `SWIFT_ACTIVE_COMPILATION_CONDITIONS` down to a local
SwiftPM target, verified with a `#warning` probe, so `#if BELAY_MAS` works in
the app and nowhere else. Every module that needs the answer asks here.

`UpdateChannel` is the seam updating goes through. `NoUpdateChannel` is what the
App Store build gets: Apple updates its own apps, and a third-party updater in a
sandboxed build is a rejection.

This module used to be `BelayTipJar` and used to hold a StoreKit tip jar behind
a `TipJarProviding` protocol. Both implementations were written, tested and
never called: no tip products were ever registered, so there was nothing for the
code to sell. It was deleted on 2026-08-16 rather than kept as a seam nobody was
walking through. What stayed is what the app actually asks.
