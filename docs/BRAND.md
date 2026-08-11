# Brand

Two marks, and they are not interchangeable.

**The symbol** is the sparkle drawn by `Sources/VigilApp/VigilGlyph.swift`. It is
the app icon and the menu bar item, it changes shape with state, and it is
generated in code rather than stored as an asset so that a state Vigil can be in
cannot fail to have a picture.

**The wordmark** is in `Resources/Brand/`: the word set in the system rounded
face at semibold, with the symbol trailing it. Use it for the README, a website,
a directory listing, a release image. Do not use it where the symbol belongs,
and do not rebuild it by typing the word next to the icon.

## Files

| File | Use |
|---|---|
| `vigil-wordmark-light.svg` | On white and light backgrounds |
| `vigil-wordmark-dark.svg` | On dark backgrounds |
| `vigil-wordmark-mono.svg` | One colour, inherits `currentColor`. Print, embroidery, a background that is neither light nor dark |
| `vigil-wordmark-{light,dark}.png` and `@2x`, `@3x` | Where SVG is not accepted |

The SVG carries **no font dependency**: the letters are outlines, not text. A
wordmark that falls back to Times on somebody else's machine is not a wordmark.
This also means the files cannot be edited by retyping the word. Regenerate them
instead, or the two halves of the lockup will disagree.

## The proportions, and why

The symbol is set to the **ascender height** of the word, not to the cap height
and not to the x-height. Nine proportions were rendered side by side and looked
at. Below the ascender the symbol reads as a speck of dust rather than as part of
the mark; above it, the word starts to look like a caption to the symbol, which
inverts what the lockup is for.

The gap is 7 units at a 36-unit word. Tighter and the symbol collides with the
`l`; wider and the lockup reads as two separate things placed near each other.

**The symbol goes after the word.** This is the one choice that looks wrong at
first, and it is deliberate: the symbol already lives on its own in the menu bar.
Putting it in front makes the wordmark an icon with a caption, which is what the
user is looking at all day anyway. Behind the word it reads as a signature, and
the lockup stays distinct from the app icon.

The word is lowercase because `vigil` is an ordinary English word, and a utility
that keeps quiet has no business shouting its own name.

## Clear space and minimum size

Keep clear space of at least half the symbol's height on every side. Nothing,
including the edge of a screenshot, comes closer.

Minimum width is 90 px. Below that the symbol's two small sparkles merge into the
large one and the mark turns into a blob. Use the symbol alone at smaller sizes.

## Colour

The accent is `#2379FF`. In the app the tint follows the user's accent colour in
System Settings, which is correct there, and the brand files are pinned so that a
README does not change colour depending on who exported it.

Never recolour the word and the symbol to the same value. They were compared
that way: matched colours flatten the lockup into one shape and the symbol stops
reading as a separate mark.
