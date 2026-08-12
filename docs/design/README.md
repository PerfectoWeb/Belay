# Superseded designs

Working versions of controls that were replaced, kept verbatim so that going
back is one `cp` rather than an archaeology exercise. Nothing here is compiled;
the `.swift.txt` extension keeps it out of the build and out of SwiftLint.

Each file is the whole view as it shipped at the time, including its doc
comment, because the reasoning in that comment is the part worth keeping.

## The mode picker

Four attempts at the same control: how a menu bar panel offers Auto, Always on
and Off. The trail matters more than any one of the files, because each attempt
was a reasonable reading of the previous one's failure.

| File | Shape | Why it was replaced |
|---|---|---|
| `mode-picker-A-segmented.swift.txt` | Stock `Picker`, three equal segments | Gave identical weight to three unequal choices, and cost a full row of a panel that is only ever glanced at |
| `mode-picker-B-menu.swift.txt` | A small menu on the headline's line | Hid the answer behind a click, in a panel whose whole job is to say what it is doing the moment it opens |
| `mode-picker-C-ring-and-pin.swift.txt` | The mark as a switch, Always on as a pin | Made the third state something the user had to work out from two controls |

The shipped control (`Sources/BelayApp/Panel/PanelModePicker.swift`) returns to
three visible targets, drawn rather than stock: one track, three tabs, and a
selection pill that slides between them. The conclusion was that the original
shape was right and the original *rendering* was wrong — a stock segmented
control reads as a form field bolted into a panel.

`PROJECT_STATE.md` D21 records the decision and the two structural defects
(panel judder, and the resize race with `NSPopover`) found on the way.

- `settings-tabs-drawn-strip.swift.txt` — the Settings switcher drawn by hand,
  with a highlight that travelled between panes and stretched into its travel.
  Replaced by the `NSToolbar` it was meant to improve on.
