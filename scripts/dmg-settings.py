# Layout for the disk image, read by dmgbuild.
#
# dmgbuild 1.6.7 or newer is required. Older versions write a second reference
# to the background picture into the .DS_Store, an NSURL bookmark under the key
# pBBk, alongside the classic alias inside icvp. Finder from macOS 26.2 onwards
# reads pBBk first and, when it finds one, draws no background at all, while
# still honouring the window size and the icon positions from the same file.
# This machine is on 26.4, which is why the picture never appeared and why
# nothing about the picture itself was ever wrong. Upstream removed the
# bookmark in dmgbuild PR #275.
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

# 540x388 of window frame for 540x360 of artwork: Finder's title bar takes 28
# points out of the frame, so asking for 360 here left a 332 point content area
# and sliced the "by PerfectoWeb" line in half.
#
# This was briefly 540x412, to leave room for the status bar some people switch
# on. It was the wrong fix and it is recorded here so nobody tries it twice: a
# window that tall needs 24 points more artwork, and adding them at the bottom
# doubled the margin under the lockup from 27 points to 51, which reads as a
# composition that has slid upwards. The scroll bar it was meant to remove was
# not caused by the window height anyway. See the icon positions below.
window_rect = ((200, 180), (540, 388))
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

# Measured off the artwork, not chosen. The panel runs x 65.5..472.5 in window
# points and the arrow's centre is at (266, 187) — the designer put it a little
# above and left of the panel's own centre, and the icons follow the arrow
# rather than the panel, because that is the line the eye reads.
#
# Each icon sits at the midpoint of its half of the panel, measured to the
# arrow rather than to the panel's centre.
# Ten points above the arrow's line rather than on it. An icon's position is
# the centre of the icon alone, but what the eye centres is the icon *and* its
# label, and the label hangs below: sitting the icons exactly on the arrow put
# that block low in the panel.
icon_locations = {
    appname: (166, 177),
    "Applications": (369, 177),
    # The two files dmgbuild has to put on the volume: the background picture
    # and the volume icon. Both are dot-prefixed, so Finder hides them from
    # anybody who has not switched hidden files on — and somebody who has
    # switched them on sees them sitting in the middle of the artwork, which is
    # how this was noticed.
    #
    # Just past the bottom edge. Finder sizes an icon view's scroll area to its
    # items and the background picture has no say in it, so leaving these three
    # unplaced let Finder auto-arrange them below the fold, which is what put a
    # scroll bar on the window in the first place and let somebody with hidden
    # files switched on scroll down and find them sitting on the artwork.
    #
    # Inside the window was tried and is worse: there is no room for three
    # 96 point icons that does not land on the panel or across the lockup, so
    # anybody showing hidden files would see them all the time rather than only
    # after deciding to scroll.
    #
    # Further away is worse too. A bigger number is a longer scroll region and a
    # smaller scroll thumb, which advertises that there is something down there.
    #
    # They cannot be removed: a background needs a file on the volume and a
    # custom volume icon needs .VolumeIcon.icns at its root. For somebody who
    # shows hidden files there is no arrangement that hides them, and this is
    # the one that keeps them off the picture.
    ".background.tiff": (58, 470),
    ".VolumeIcon.icns": (158, 470),
    ".fseventsd": (258, 470),
}
