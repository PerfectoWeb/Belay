#!/usr/bin/env bash
# The mechanical half of docs/QA-CHECKLIST.md, for a clean macOS with no
# developer tools on it.
#
#   bash qa-vm.sh /path/to/Belay.app
#
# Uses nothing but what ships with macOS: no Xcode, no Homebrew, no network.
# Copy this file and Belay.app into the VM, run it, and send back everything it
# prints. It does not judge anything as a pass — it states what it saw, because
# a script that decides for you is a script that hides the interesting failure.
#
# What it cannot do is look at the screen. Six panes drawing correctly, the
# panel opening, and the login item sticking still need eyes; the checklist
# lists those separately.
set -u

APP="${1:-}"
[ -n "$APP" ] || APP="$(cd "$(dirname "$0")" && pwd)/Belay.app"
BUNDLE="com.perfectoweb.belay"

say() { printf '\n=== %s ===\n' "$1"; }

say "machine"
sw_vers
uname -m
echo "Parallels/VM: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)"

say "the app"
if [ ! -d "$APP" ]; then
    echo "NOT FOUND: $APP"
    echo "Pass the path as the first argument."
    exit 1
fi
echo "$APP"
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null
codesign -dv "$APP" 2>&1 | grep -E "Signature|Identifier|TeamIdentifier" || true

# Which preferences file this build reads. A sandboxed build (the App Store
# one) has its own container and never looks at ~/Library/Preferences, so
# writing there sets a mode the app cannot see: it launches on the defaults,
# holds nothing in alwaysOn, and every line below reads like a power bug.
# That is what happened on the first macOS 15 run.
say "preferences domain"
if codesign -d --entitlements - "$APP" 2>/dev/null | grep -q "app-sandbox"; then
    PREFS="$HOME/Library/Containers/$BUNDLE/Data/Library/Preferences/$BUNDLE.plist"
    echo "sandboxed build -> container"
else
    PREFS="$HOME/Library/Preferences/$BUNDLE.plist"
    echo "unsandboxed build -> home"
fi
echo "$PREFS"
mkdir -p "$(dirname "$PREFS")"

# Gatekeeper refuses a downloaded ad-hoc build until this is off. Removing the
# quarantine flag from a build you made yourself is the same decision as the
# right-click Open dialog, minus the dialog.
say "quarantine"
if xattr -p com.apple.quarantine "$APP" >/dev/null 2>&1; then
    xattr -dr com.apple.quarantine "$APP" && echo "removed (this is what the scary dialog was about)"
else
    echo "none"
fi

stop() { osascript -e "tell application id \"$BUNDLE\" to quit" >/dev/null 2>&1; sleep 2; }
start() { open "$APP" >/dev/null 2>&1; sleep 4; }
pid() { pgrep -x Belay 2>/dev/null | head -1; }

# Every assertion line macOS attributes to *our* pid. Grepping for the word
# "belay" also matches runningboardd's launch assertion, which is not ours.
assertions() {
    local p; p="$(pid)"
    [ -n "$p" ] && pmset -g assertions | grep "pid $p(" || true
}

say "launch"
stop
start
if [ -z "$(pid)" ]; then
    echo "DID NOT LAUNCH. Everything below is meaningless; send the newest file from"
    echo "~/Library/Logs/DiagnosticReports/ that mentions Belay."
    ls -t ~/Library/Logs/DiagnosticReports/ 2>/dev/null | head -5
    exit 1
fi
echo "running, pid $(pid)"

for mode in alwaysOn off auto; do
    say "mode: $mode"
    stop
    # By path, not by domain. `defaults write com.perfectoweb.belay …` looks
    # right and lands somewhere the app does not read as soon as a sandboxed
    # build of the same bundle id has ever run on the machine — the App Store
    # build's container wins the domain. An hour went into that on the
    # development Mac; the file form works everywhere.
    defaults write "$PREFS" mode -string "$mode"
    killall cfprefsd 2>/dev/null || true
    sleep 1
    start
    echo "written: $(defaults read "$PREFS" mode 2>/dev/null)"
    # What the app itself read, which is the only number that means anything.
    echo "app read: $(/usr/bin/log show --predicate 'subsystem BEGINSWITH "com.perfectoweb.belay"' \
        --last 30s --style compact 2>/dev/null | grep -o 'mode [a-zA-Z]*' | tail -1)"
    held="$(assertions)"
    if [ -n "$held" ]; then echo "$held"; else echo "(no assertion held)"; fi
done

say "expected"
cat <<'EOF'
alwaysOn  ->  PreventUserIdleSystemSleep named "Belay", with
              "Timeout will fire in N secs Action=TimeoutActionRelease"
off       ->  no assertion
auto      ->  no assertion unless a coding agent is running on this machine
EOF

say "crashes since boot"
ls -t ~/Library/Logs/DiagnosticReports/ 2>/dev/null | grep -i belay | head -5 || echo "none"

say "log, last two minutes"
# --info matters: everything the power layer says about holding and releasing
# is logged at info level, and log show drops that level unless asked.
/usr/bin/log show --predicate 'subsystem BEGINSWITH "com.perfectoweb.belay"' --info --last 2m --style compact 2>/dev/null | tail -30 \
    || echo "(none)"

say "left for a person"
cat <<'EOF'
Open Settings from the menu bar icon and look at all six panes: General,
Providers, Behaviour, Notifications, Statistics, About. Nothing empty, nothing
clipped, no control drawn over another. Then General, tick "Open at login",
untick it: both have to stick.

Send this output plus a screenshot of anything that looks wrong.
EOF
