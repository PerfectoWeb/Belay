#!/usr/bin/env bash
# Photographs every screen Belay has, in whatever language it is running in.
#
#   ./scripts/shoot-screens.sh                     # all of them, current language
#   ./scripts/shoot-screens.sh --language zh-Hans  # ...in Chinese
#   ./scripts/shoot-screens.sh --welcome           # just the welcome screen
#   ./scripts/shoot-screens.sh --panel --settings  # any combination
#   ./scripts/shoot-screens.sh --out /tmp/shots    # somewhere other than build/screens
#
# Why this exists. A translation that is correct on paper can still clip a
# button, wrap a mode name onto two lines or push a session row past the panel's
# width, and none of that is visible from the CSV. Neither is an animation that
# eases wrongly. This is the way to look without asking somebody to look.
#
# It drives the real app on a real screen. That means two things it cannot work
# around: the screen has to be unlocked and awake, and this terminal needs
# permission to send Apple events to System Events. Both fail loudly below
# rather than producing a folder of black rectangles.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/build/Belay.app"

# Addressed by path, and that is not a style choice. A container exists for this
# bundle id from the sandboxed App Store build, and once it does, `defaults write
# com.perfectoweb.belay …` writes there instead. The directly built app is not
# sandboxed and reads ~/Library/Preferences, so the short form silently writes to
# a domain the running app never reads: the welcome flag never clears, the window
# never opens, and nothing reports an error.
DOMAIN="$HOME/Library/Preferences/com.perfectoweb.belay"

OUT="$ROOT/build/screens"
LANGUAGE=""
WANT_WELCOME=0
WANT_PANEL=0
WANT_SETTINGS=0

while [ $# -gt 0 ]; do
    case "$1" in
        --welcome) WANT_WELCOME=1 ;;
        --panel) WANT_PANEL=1 ;;
        --settings) WANT_SETTINGS=1 ;;
        --language) LANGUAGE="${2:?--language needs a code, for example zh-Hans}"; shift ;;
        --out) OUT="${2:?--out needs a directory}"; shift ;;
        -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
if [ $((WANT_WELCOME + WANT_PANEL + WANT_SETTINGS)) -eq 0 ]; then
    WANT_WELCOME=1; WANT_PANEL=1; WANT_SETTINGS=1
fi

[ -d "$APP" ] || { echo "no app at $APP; run scripts/build-local.sh first" >&2; exit 1; }
mkdir -p "$OUT"

say() { echo "  $*"; }

# --- the two things that make this fail as a black rectangle -----------------

probe="$OUT/.probe.png"
if ! screencapture -x -R 0,0,8,8 "$probe" 2>/dev/null; then
    echo "the screen is locked or asleep: screencapture cannot read it" >&2
    echo "unlock the Mac and run this again" >&2
    exit 1
fi
rm -f "$probe"

events() { osascript -e "tell application \"System Events\" to tell process \"Belay\" to $1"; }

if ! osascript -e 'tell application "System Events" to get name' >/dev/null 2>&1; then
    cat >&2 <<'MSG'
this terminal is not allowed to send Apple events to System Events, so the
panel cannot be opened and window frames cannot be read.

  System Settings > Privacy & Security > Automation
  find this terminal, and switch on "System Events"

A rename of the enclosing folder is enough to revoke it, because macOS keys the
grant to the calling program.
MSG
    exit 1
fi

# --- the app, in the language asked for --------------------------------------

restart() {
    pkill -x Belay 2>/dev/null || true
    sleep 1
    open "$APP"
    sleep 4
}

if [ -n "$LANGUAGE" ]; then
    defaults write "$DOMAIN" AppleLanguages -array "$LANGUAGE"
    say "language set to $LANGUAGE"
fi

# The frame of the app's frontmost real window, or nothing. The panel is not one
# of these: it is an NSPanel and System Events does not list it.
window_frame() {
    events 'get {position, size} of window 1' 2>/dev/null | tr -d ' '
}

shoot_frame() {
    local frame="$1" file="$2"
    IFS=, read -r x y w h <<<"$frame"
    screencapture -x -R "$x,$y,$w,$h" "$file"
}

# --- the welcome screen, which exists only until it is dismissed -------------

if [ "$WANT_WELCOME" = 1 ]; then
    defaults write "$DOMAIN" hasCompletedOnboarding -bool false
    restart
    frame=""
    for _ in 1 2 3 4 5 6; do
        frame="$(window_frame)"; [ -n "$frame" ] && break
        sleep 2
    done
    if [ -n "$frame" ]; then
        shoot_frame "$frame" "$OUT/welcome.png"
        say "welcome  ${frame#*,*,}"
    else
        say "welcome: no window appeared, flag reads $(defaults read "$DOMAIN" hasCompletedOnboarding)"
    fi
fi

# Out of the way for everything else.
defaults write "$DOMAIN" hasCompletedOnboarding -bool true
restart

# --- the panel ---------------------------------------------------------------
#
# Found by difference rather than by coordinates. The panel is an NSPanel, so
# System Events cannot give its frame, and the status item sits at a different
# place on every menu bar and every display. Photographing the region before and
# after the click and taking the bounding box of what changed gives the panel
# exactly, and answers "did the click open it or close it" in the same step.

panel_shot() {
    local item region before after
    item="$(events 'get {position, size} of menu bar item 1 of menu bar 2' 2>/dev/null | tr -d ' ')" || return 1
    [ -n "$item" ] || return 1
    IFS=, read -r ix iy iw ih <<<"$item"
    # A generous box hanging under the item, wider than the panel so its shadow
    # is inside it, and clamped at the left edge of the display. The panel opens
    # below the menu bar and roughly under the item; the exact frame is worked
    # out from the difference below, so this only has to contain it.
    local width=680 height=560 left top
    left=$(( ix + iw / 2 - width / 2 )); [ "$left" -lt 0 ] && left=0
    top=$(( iy + ih ))
    region="$left,$top,$width,$height"

    before="$OUT/.before.png"; after="$OUT/.after.png"
    screencapture -x -R "$region" "$before"
    events 'click menu bar item 1 of menu bar 2' >/dev/null 2>&1 || true
    sleep 1.3
    screencapture -x -R "$region" "$after"
    python3 - "$before" "$after" "$OUT/panel.png" <<'PY'
import sys
from PIL import Image, ImageChops
before, after, out = (Image.open(sys.argv[1]).convert("RGB"),
                      Image.open(sys.argv[2]).convert("RGB"), sys.argv[3])
box = ImageChops.difference(before, after).getbbox()
if box is None:
    raise SystemExit("the click changed nothing on screen: the panel did not open")
# A little air, so the shadow and the rounded corners are not shaved off.
pad = 6
left, top, right, bottom = box
after.crop((max(0, left - pad), max(0, top - pad),
            min(after.width, right + pad), min(after.height, bottom + pad))).save(out)
print(f"  panel  {right - left} x {bottom - top}")
PY
    rm -f "$before" "$after"
}

if [ "$WANT_PANEL" = 1 ]; then
    panel_shot || say "panel: could not find the status item"
fi

# --- settings, one photograph per pane ---------------------------------------

if [ "$WANT_SETTINGS" = 1 ]; then
    # The gear is in the panel's bottom right corner and the panel is open,
    # because the shot above left it that way. Asking the menu bar instead keeps
    # this independent of where that gear happens to sit.
    events 'click menu bar item 1 of menu bar 2' >/dev/null 2>&1 || true
    sleep 0.6
    osascript -e 'tell application "System Events" to tell process "Belay" to keystroke "," using command down' \
        >/dev/null 2>&1 || true
    sleep 2.5
    tabs="$(events 'get name of every button of toolbar 1 of window 1' 2>/dev/null || true)"
    if [ -z "$tabs" ]; then
        say "settings: the window did not open"
    else
        IFS=', ' read -r -a names <<<"$tabs"
        for tab in "${names[@]}"; do
            [ -n "$tab" ] || continue
            events "click button \"$tab\" of toolbar 1 of window 1" >/dev/null 2>&1 || continue
            sleep 1.4
            frame="$(window_frame)"; [ -n "$frame" ] || continue
            shoot_frame "$frame" "$OUT/settings-$tab.png"
            say "settings/$tab  ${frame#*,*,}"
        done
    fi
fi

echo "  -> $OUT"
