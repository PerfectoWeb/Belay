#!/usr/bin/env python3
"""Guards the disk image window against the two ways it has already been broken.

    python3 scripts/check-dmg-layout.py

The layout in `dmg-settings.py` was signed off by eye, twice, after two failed
attempts that each looked reasonable in the diff. This turns that sign-off into
something a machine can check, because the failures are not visible in the
source: they only show up in a Finder window on somebody else's Mac, and the
person who wrote the change is the least likely to see them.

What it enforces, and why each rule exists:

  The window is 540x388 for a 540x360 picture. It was grown to 540x412 once, to
  make room for the status bar some people switch on, and the artwork was
  extended to match. That doubled the margin under the lockup from 27 points to
  51 and the composition read as having slid upwards. It was also unnecessary:
  the scroll bar it was meant to remove came from the icon positions, not from
  the window height.

  No item reaches further left or right than the visible pair does. Finder lays
  an icon view out against the extent of its items, not against the window, so
  an item further out than `Belay.app` or `Applications` drags the whole grid
  sideways relative to the background. That is what made the window look square
  with hidden files off and out of true with them on. Sitting between them is
  fine; sticking out past them is not.

  The three dot-files sit below the window and the two real ones sit inside it.
  Unplaced, Finder auto-arranges them below the fold and that is what puts a
  scroll bar on the window in the first place.
"""
import re
import sys

SETTINGS = "scripts/dmg-settings.py"

WINDOW = (540, 388)
CONTENT_HEIGHT = 388 - 28  # Finder's title bar takes 28 points out of the frame.
ICON = 96
VISIBLE = {"appname", "Applications"}
HIDDEN = {".background.tiff", ".VolumeIcon.icns", ".fseventsd"}


def fail(message):
    print(f"dmg layout: {message}", file=sys.stderr)
    sys.exit(1)


source = open(SETTINGS, encoding="utf-8").read()

size = re.search(r"^window_rect = \(\(\d+, \d+\), \((\d+), (\d+)\)\)", source, re.M)
if not size:
    fail("no window_rect in " + SETTINGS)
if (int(size.group(1)), int(size.group(2))) != WINDOW:
    fail(
        f"the window is {size.group(1)}x{size.group(2)}, expected {WINDOW[0]}x{WINDOW[1]}. "
        "Growing it needs a taller background or the composition slides upwards; "
        "read the note above window_rect before changing this."
    )

block = re.search(r"^icon_locations = \{(.*?)^\}", source, re.M | re.S)
if not block:
    fail("no icon_locations in " + SETTINGS)

placed = {
    name.strip("\"'"): (int(x), int(y))
    for name, x, y in re.findall(r'^\s*([^\s:#]+):\s*\((\d+),\s*(\d+)\)', block.group(1), re.M)
}

missing = (VISIBLE | HIDDEN) - placed.keys()
if missing:
    fail(f"nothing placed for {sorted(missing)}. An unplaced item is auto-arranged below "
         "the window, which is what puts a scroll bar on it.")

left = min(placed[name][0] for name in VISIBLE) - ICON // 2
right = max(placed[name][0] for name in VISIBLE) + ICON // 2
for name in HIDDEN:
    x, y = placed[name]
    if x - ICON // 2 < left or x + ICON // 2 > right:
        fail(f"{name} at x={x} reaches outside {left}..{right}, the span the visible icons "
             "occupy. Widening that span moves the whole grid sideways relative to the "
             "background.")
    if y - ICON // 2 <= CONTENT_HEIGHT:
        fail(f"{name} is at y={y}, which is inside the {CONTENT_HEIGHT} point window. "
             "It would sit on the artwork for anybody who shows hidden files.")

for name in VISIBLE:
    _, y = placed[name]
    if y + ICON // 2 > CONTENT_HEIGHT:
        fail(f"{name} is at y={y} and falls outside the {CONTENT_HEIGHT} point window.")

print(f"  ok  window {WINDOW[0]}x{WINDOW[1]}, {len(placed)} items, "
      f"all within x {left}..{right}, hidden ones below the fold")
