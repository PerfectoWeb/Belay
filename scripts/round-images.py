#!/usr/bin/env python3
"""Rounds the corners of the README's images and gives them room to breathe.

    python3 scripts/round-images.py source.png=out.png [...]

Two things GitHub will not let a README do, both baked into the file instead:

  Rounding. GitHub sanitises `style` out of README HTML, so a border-radius
  written there is dropped in silence. An alpha mask survives, and because it is
  alpha rather than a painted corner it works in both GitHub themes.

  Spacing. Images laid side by side get whatever gap the paragraph's line-height
  happens to give, which is wide across and thin down. A transparent margin in
  the file itself is the only gap that is the same in both directions.

The radius is a fraction of the image's own width rather than a pixel count, so
every picture comes out with the same curve after GitHub scales them all to
different widths.
"""
import sys
from PIL import Image, ImageDraw

RADIUS = 0.038
MARGIN = 0.012

for pair in sys.argv[1:]:
    path, out = pair.split("=")
    im = Image.open(path).convert("RGBA")
    radius = max(16, round(im.width * RADIUS))
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [(0, 0), (im.width - 1, im.height - 1)], radius=radius, fill=255)
    im.putalpha(mask)

    margin = round(im.width * MARGIN)
    if margin:
        padded = Image.new("RGBA", (im.width + margin * 2, im.height + margin * 2), (0, 0, 0, 0))
        padded.alpha_composite(im, (margin, margin))
        im = padded
    im.save(out, optimize=True)
    print(f"  {out}  {im.size}  r={radius} margin={margin}")
