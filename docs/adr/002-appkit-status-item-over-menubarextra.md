# 002 — AppKit `NSStatusItem` over SwiftUI `MenuBarExtra`

**Status:** accepted, implemented in M1

## Context

Vigil is a menu bar app and nothing else — `LSUIElement`, no Dock icon, no
window on launch. The entire product surface is a 2 mm monochrome glyph and a
panel that drops from it. SwiftUI offers `MenuBarExtra(.window)`, which would let
the whole UI be SwiftUI with no AppKit at all.

Two things make that attractive: less code, and a `Settings` scene that comes
free. Two things make it risky: `MenuBarExtra` still has rough edges around focus
handling, dismissal and right-click, and macOS 26's menu bar renders status items
differently enough that precise control over template-image rendering matters.

## Decision

Use `NSStatusItem` with `variableLength` and a template `NSImage`, and host
SwiftUI views inside it through `NSHostingController` in an `NSPopover`.

The status item's image is always `isTemplate = true`. No colour literal appears
anywhere in the status item code; that single flag is what makes light, dark,
tinted, and reduced-transparency menu bars all work without a code path each.

State is conveyed by **shape**, never by motion. There is no animation on the
icon at any point.

## Consequences

- Right-click, dismissal and focus behave the way every other menu bar utility
  behaves, because they are the same API every other menu bar utility uses.
- The panel is still SwiftUI, so the ergonomics win is mostly kept: only the
  ~120 lines of `StatusItemController` are AppKit.
- The popover is created lazily and torn down when hidden. A SwiftUI view that
  still exists while the panel is closed keeps re-rendering, which `docs/08`
  names as a common cause of blowing the idle CPU budget.
- A no-animation icon costs nothing per frame. A pulsing menu bar icon burns a
  redraw continuously and reads as cheap.
- We own the accessibility label and keep it in sync with state, rather than
  hoping the framework infers something reasonable from a glyph.

Cost, accepted: an `AppState` bridge object is needed so the AppKit status item
learns about changes, since it cannot participate in Observation tracking the way
a SwiftUI view does. That is one explicit `onChange` callback.

## Alternatives considered

**`MenuBarExtra(.window)`.** Rejected for the focus/dismissal/right-click rough
edges and the loss of control over icon rendering. Worth revisiting once the
deployment target moves past macOS 14 and the API has settled — the panel view
itself is already SwiftUI and would port unchanged.

**`MenuBarExtra(.menu)`.** Cannot express the session list, the mode picker and
the footer that `docs/05` specifies. A plain menu is not enough UI.

**Pure AppKit, no SwiftUI at all.** Considered for the memory footprint, and
rejected once measured: `footprint` reports a 15.1 MB `phys_footprint` against a
40 MB budget with SwiftUI present, so there is nothing to buy. (An early ~72 MB
figure was `ps -o rss=`, which counts shared framework pages and is the wrong
metric for this budget.) Hand-writing layout for a list and a picker would cost
a lot of code to save nothing.
