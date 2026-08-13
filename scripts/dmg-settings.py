# Layout for the disk image, read by dmgbuild.
#
# dmgbuild is used instead of create-dmg because create-dmg drives Finder over
# Apple Events to arrange the window. That needs Automation permission, which
# a build machine does not have and cannot be given non-interactively, and it
# fails late when the permission is missing. dmgbuild writes the .DS_Store
# itself, so the same command works on a laptop, over ssh and in CI.
#
# Coordinates are in window points with the origin at the top left, and they
# come from measuring the artwork rather than from taste: the background has a
# panel drawn on it, and the icons have to land inside it.

import os.path

# dmgbuild exec()s this file without setting __file__, so the repository root
# arrives as a define instead of being derived from this file's own path.
root = defines.get("root", os.getcwd())  # noqa: F821

application = defines.get("app", os.path.join(root, "dist/export/Belay.app"))  # noqa: F821
appname = os.path.basename(application)

format = "UDZO"
compression_level = 9
files = [application]
symlinks = {"Applications": "/Applications"}

# `icon`, not `badge_icon`. The latter stamps a small image onto macOS's own
# grey removable-disk icon; this replaces it outright, which is what puts a
# drive in Belay's blue on the desktop next to WhatsApp's green one.
icon = os.path.join(root, "Promo/dmg/VolumeIcon.icns")
background = os.path.join(root, "Promo/dmg/background.tiff")

# 540x360 points. The artwork is 1080x720, which makes it an exact 2x asset at
# this size: no resampling, and the same proportions CleanMyMac uses. Treating
# 1080x720 as the point size instead would open a window three quarters the
# width of a laptop screen.
window_rect = ((200, 180), (540, 360))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
arrange_by = None
grid_offset = (0, 0)
label_pos = "bottom"
text_size = 13
icon_size = 96

# The panel in the artwork runs x 65.5..472.5 and y 108..271 in window points.
# Each icon sits at the midpoint of its half of that panel, level with the
# arrow between them.
icon_locations = {
    appname: (167, 190),
    "Applications": (371, 190),
}
