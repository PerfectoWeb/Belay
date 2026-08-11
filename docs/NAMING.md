# Naming

## Working name: **Vigil**

Short, pronounceable in both English and Russian ("Виджил"), means "staying
awake and watching over something", and has no collision with an Apple term.

**Before M6, search the Mac App Store and USPTO/EUIPO for conflicts.** If
"Vigil" is taken by a similar utility, switch — the rename is cheap if you
follow the procedure below, and expensive after launch.

## Alternatives, in the order I'd pick them

| Name | Note |
|---|---|
| **Nocturne** | Elegant, matches the overnight use case; possible music-app collisions |
| **Wakeful** | Descriptive, friendly, likely available |
| **Lantern** | Warm, memorable, less literal |
| **Perch** | Short, odd in a good way, very available |
| **Sentry** | Clear but crowded — many security products use it |

Avoid: anything with "Caffeine", "Awake", "NoSleep", "Amphetamine" — the
category is saturated and the names are unregistrable.

## Identifiers

Replace `<org>` with the user's reverse-DNS domain once known.

```
Bundle ID (direct)  com.<org>.vigil
Bundle ID (MAS)     com.<org>.vigil        # same; different provisioning
Helper              com.<org>.vigil.hook
App group           <TEAMID>.com.<org>.vigil
Log subsystem       com.<org>.vigil
Defaults suite      com.<org>.vigil
```

Team ID and org domain are unknown to you. Define them **once** in
`project.yml` as `PRODUCT_NAME` / `ORG_IDENTIFIER` / `DEVELOPMENT_TEAM`
variables, reference them everywhere else, and record in `BLOCKERS.md` that the
user must fill in the team ID before a signed release.

## Rename procedure

Because everything derives from `project.yml` variables and a single
`Branding.swift` constants file, renaming is:

1. change `PRODUCT_NAME` and `ORG_IDENTIFIER` in `project.yml`
2. update `Sources/VigilApp/Branding.swift`
3. `xcodegen generate`
4. rename the `Vigil*` package directories if you care about cosmetics

Do not scatter the product name through source strings. Every user-visible
occurrence comes from `Branding.appName` or the string catalog.
