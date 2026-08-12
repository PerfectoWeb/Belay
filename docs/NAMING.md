# Naming

## Settled, 2026-08-12: the app is **Belay**

A belay is the person holding the rope so the one doing the work cannot fall.
That is the product, and it is a verb rather than a state, which "Vigil" never
was: "vigil" is staying awake, "belay" is holding so the one working does not
come off.

### Why the old name had to go

The B4 search was run against **Vigil** and it was not a near miss:

- **Mac App Store** had **"Vigil - Stay Awake"** in Utilities, a menu bar
  sleep-prevention tool. Same word, same category, same job. "Vigilante - Stay
  Awake" sat beside it.
- **USPTO** has a live registration for the word VIGIL in class 009 covering
  computer software (reg. 2385400, Vigil Health Solutions, since 2000), plus a
  pending VIGIL in 042 for SaaS.
- **EUIPO** has Vigil Health Solutions registered to 2030, and refused a VIGIL
  class-9 application from Stanley Black & Decker. The class is crowded.

### What Belay's own field looks like

Two App Store apps carry the word: an SSH client in Developer Tools and a to-do
app in Productivity. Neither is a utility and neither is about sleep, so there
is no collision that matters, but the field is not empty and that was known
when the name was chosen.

Three other finalists were searched and rejected. **Kedge** has kedge.dev, a
deployment platform, which is the same broad space we are in, plus KEDGE
Business School's apps. **Pawl** has a pet app on Google Play and a PHP
WebSocket library. **Prusik** turned up nothing in software and was the
cleanest field of the four, but it needs explaining to anyone who does not
climb, and a name that needs explaining loses to one that does not.

Still owed: the formal USPTO and EUIPO checks in classes 009 and 042, and the
domain. A web search is not a register search.

### What did not change

The icon, the wordmark's typeface and the sparkle mark are the same artwork as
before. Only the word was redrawn, from the same SF Pro Rounded semibold
outlines, by the same script.

## Identifiers

```
Bundle ID (direct)  com.perfecto-web.belay
Bundle ID (MAS)     com.perfecto-web.belay      # same; different provisioning
Helper              com.perfecto-web.belay.hook
App group           <TEAMID>.com.perfecto-web.belay
Log subsystem       com.perfecto-web.belay
Defaults suite      com.perfecto-web.belay
```

`ORG_IDENTIFIER` and `PRODUCT_NAME` live in `project.yml` and everything else
derives from them. The team ID is still owed before a signed release; see
`BLOCKERS.md`.

## Rename procedure, as actually run

The claim here used to be that renaming was a two-file change. It was not, and
the Vigil to Belay pass is the record of what it really takes:

1. rename every path containing the old word, deepest first, with `git mv`
2. rewrite the word in every text file, with a negative lookahead so the
   Spanish "vigilando" in the translations survives
3. re-sort the leading import block in every Swift file, because renaming the
   modules moved them in the alphabet
4. regenerate the wordmark outlines and rasterise them at the established
   scale, which is twice the SVG units at 1x
5. `xcodegen generate`, then the full gate
6. rename the repository on GitHub and update the remote

Steps 3 and 4 are the ones that were not in the old procedure and are the ones
that break the build and the About pane respectively.

Do not scatter the product name through source strings. Every user-visible
occurrence comes from `Branding.appName` or the string catalogue.
