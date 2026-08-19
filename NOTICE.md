# Notices

Belay itself is under the Belay Source-Available License 1.0, see `LICENSE`:
free to use and to build on, never to sell, and it must be credited. The name "Belay" and the Belay
marks are not part of that licence, see `docs/TRADEMARKS.md`: the code is yours to
take, the name is not yours to ship.

## Third-party trademarks and logos

Belay bundles the marks of the tools it can watch, in
`Resources/Assets.xcassets/logo-*.imageset`, and shows them in the Active
Sessions list so you can tell at a glance which agent is running.

**All product names, logos, trademarks and registered trademarks are the
property of their respective owners.** They appear here only to identify those
products. Their use does not imply any affiliation with, sponsorship by, or
endorsement from their owners, and none of these companies are involved with
Belay in any way.

| Mark | Owner |
|---|---|
| Claude, Claude Code | Anthropic PBC |
| ChatGPT, Codex, OpenAI | OpenAI, Inc. |
| Gemini | Google LLC |
| Cline | Cline Bot Inc. |

The artwork is rendered as a monochrome template image so it takes the colour of
the surrounding interface. That is a deliberate interface choice, because a row of
brand colours in a menu bar panel is noise, and it does mean the marks are not
shown in their owners' specified colours. If you own one of these marks and want
it presented differently, or not at all, open an issue and it will be changed.

Belay ships no artwork it does not have the right to ship. If you are packaging
a fork for distribution, that responsibility becomes yours.

## Third-party sounds

Two recordings come from Pixabay. Every other sound in `Resources/Sounds` is
synthesised by `scripts/make-sounds.swift`; these are the deliberate
exception, and this is their provenance, verified against each sound's page
on 2026-08-19:

- `welcome-spell.mp3` — "Magic Spell" by freesounds123,
  pixabay.com/sound-effects/magic-spell-333896/
- `welcome-cinematic.mp3` — "Hybrid Cinematic - 15 sec" by LiteSaturation,
  pixabay.com/sound-effects/hybrid-cinematic-15-sec-213055/

Both are under the Pixabay Content License: free for commercial use, no
attribution required — credited here anyway, because it costs two lines.

`whats-new.wav` is the first strike cut from a chime the project's author
supplied; it is part of Belay like the synthesised files are.
The licence forbids redistributing content "on a standalone basis"; these
files ship inside the app and inside its source tree as part of a larger
work, which is the use the licence describes, not the one it forbids. Anyone
extracting the files from either to pass along on their own is outside it.
