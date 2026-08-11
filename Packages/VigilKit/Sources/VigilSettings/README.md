# VigilSettings

Vigil's preferences, typed and clamped, plus the schema versioning that lets them
change later.

`SettingsStore` is the `@MainActor @Observable` object the UI binds to.
`SettingsValues` is the whole preference set as one value type; `SettingsBounds`
is the range each one is squeezed into; `SettingsSchema` migrates and stamps the
domain. `SettingsPresets` is the data the Behaviour pane's pickers render.

**Depends on:** `VigilSupport` and `VigilCore`.

## Things that might surprise you

**The dependency points this way round, and that is the point.** `AwakePolicy`
lives in `VigilCore`; this module builds one from what is on disk. So the
coordinator never sees `UserDefaults`, and `SettingsValues.default` is derived
from `AwakePolicy.default` so the two cannot drift apart.

**Everything numeric is clamped twice** — once when read from the plist, once on
every write, through the single `update` path. A preferences plist is a file the
user can edit and a bad migration can corrupt, so nothing read back is trusted.
The ceilings exist to protect the safety invariants: an `assertionTimeout` longer
than its refresh, or a `sessionTTL` long enough to keep a dead session alive, both
pin the Mac awake with nobody watching.

**`nil` is stored as an explicit flag, never as a magic zero.**
`maxContinuousAwakeUnlimited` and `batteryGuardEnabled` are separate booleans, and
the last finite value is deliberately left behind — so turning the battery guard
off and back on restores the threshold the user chose rather than resetting to the
default.

**A store written by a newer Vigil is ignored, not guessed at.**
`futureSchema` runs on defaults, because a layout this build has never seen is
unreadable by definition. Writes still persist, so Settings does not silently
become read-only.

**`SettingsKey: CaseIterable` is load-bearing.** It is how migration distinguishes
a genuinely fresh install (none of our keys present) from a build that predates
versioning (our keys present, no schema stamp). Adding a key means adding a case,
not a string literal somewhere.

**Migration never throws and never wipes.** Preferences are not worth crashing
over. Adding version 2 is meant to be boring: bump `current`, append one `Step`,
and the existing tests cover the mechanism.
