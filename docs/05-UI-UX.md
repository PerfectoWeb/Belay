# 05 — UI & UX

Design intent: **a good citizen of the menu bar.** It should feel like something
Apple could have shipped — quiet, monochrome, instantly legible, never in the
way. Nothing bounces, nothing animates without a reason, nothing asks for
attention it hasn't earned.

## Status item

Use `NSStatusItem` + `NSPopover` (AppKit) rather than SwiftUI's `MenuBarExtra`.
`MenuBarExtra(.window)` still has rough edges around focus, dismissal and
right-click, and we need precise control over icon rendering on Tahoe's Liquid
Glass menu bar. Host SwiftUI views inside via `NSHostingView` — you get SwiftUI
ergonomics and AppKit control.

- `NSStatusItem` with `variableLength`, `button.image` set to a **template**
  image (`image.isTemplate = true`). Never hardcode black or white; the template
  flag is what makes light/dark/tinted/reduced-transparency all work for free.
- Prefer a custom SF Symbol (`.symbolRenderingMode(.monochrome)`) exported from
  SF Symbols.app so it inherits weight and optical sizing correctly. Fall back
  to system symbols if that's a time sink in M1.
- Left click → panel. Right click / control-click → a compact `NSMenu` with
  Mode, Settings…, About, Quit.
- **No animation on the icon.** A pulsing menu bar icon is the fastest way to
  make a utility feel cheap and to burn CPU on every frame. State is conveyed by
  shape, not motion.

### Icon states

| State | Symbol intent |
|---|---|
| Off | outlined moon with a slash |
| Armed (auto, nothing running) | outlined moon |
| Working | filled moon / solid mark |
| Awaiting user | filled mark + a small dot badge |
| Error (e.g. lost folder access) | outlined mark with an exclamation |

The user must be able to tell "is it holding the Mac awake right now?" from a
2 mm monochrome glyph at a glance. Test this by actually looking at it, at
normal display scaling, in both appearances.

## The panel

Width 330 pt — raised from ~300 once the state descriptions were written, and
the block that holds them reserves two lines so switching modes cannot change
the panel's height. Top to bottom:

1. **Status line** — plain language, no jargon: "Keeping your Mac awake" /
   "Your Mac will sleep normally" / "Claude Code is waiting for you".
2. **Mode picker** — segmented: Auto · Always on · Off. One tap.
3. **Active sessions** — a compact list, each row: provider glyph, workspace
   name, state, elapsed. Empty state: "No active sessions." Cap the visible list
   at 5 with "+N more".
4. **Footer** — total awake time this session, and a link to Settings.

If a provider needs setup (e.g. folder access not granted), show a single
inline row with a one-tap fix, not a modal.

## Settings window

Standard `SwiftUI` `Settings` scene with a `TabView`, macOS-native sizing.
Panes:

- **General** — launch at login (`SMAppService.mainApp`), show elapsed time in
  menu bar (off by default), appearance of the icon
- **Providers** — one section per provider, generated from metadata: enable
  toggle, availability status, "Grant access to ~/.claude" button, "Enable
  precise detection (hooks)" with the diff preview and a Remove button
- **Behaviour** — grace period (30 s / 90 s / 3 min / custom), keep display
  awake, awaiting-user budget, max continuous awake time, battery guard
  threshold, Low Power Mode behaviour
- **Notifications** — notify when an agent needs input, when a long task
  finishes, when the max-duration cap releases the assertion
- **Updates** — direct build only; hidden entirely in the App Store build
- **About** — version, build, links, acknowledgements, Tip Jar

Every setting needs a sensible default such that a user who never opens this
window gets the right behaviour. If a setting can't be defaulted well, it
probably shouldn't exist.

## Onboarding

Exactly one screen, shown on first launch, dismissible:

1. What Vigil does, in two sentences.
2. **The privacy statement, prominently**: "Vigil reads only enough of your
   local agent's session files to know whether it's running. It never reads your
   prompts or code, and nothing ever leaves your Mac."
3. One button: "Grant access to ~/.claude" → `NSOpenPanel` pre-pointed at the
   folder, result stored as a security-scoped bookmark.
4. A "Skip for now" that leaves the app functional in manual mode.

Do not build a five-step wizard. Do not ask for notification permission on
launch — request it lazily, the first time a notification would actually fire.

## Notifications

`UNUserNotificationCenter`, no more than one per event, never repeated for the
same session. Categories:

- *Agent needs your input* — with a "Keep awake 15 more minutes" action
- *Task finished* — only if the run exceeded a threshold (default 5 min), and
  only if the app isn't frontmost
- *Released for safety* — max duration or battery guard

Notification fatigue kills utilities. Default the "task finished" one **on**
(it's the delight moment) and everything else conservative.

## Accessibility & localisation

- Every control has an accessibility label; the status item has a descriptive
  `accessibilityLabel` reflecting current state.
- Full keyboard navigation in the panel and settings.
- Respect Reduce Motion and Increase Contrast.
- All strings in `String Catalog` (`.xcstrings`) from day one, even if only
  English ships in 1.0. Russian is the obvious second locale; leave the file
  ready for it.
