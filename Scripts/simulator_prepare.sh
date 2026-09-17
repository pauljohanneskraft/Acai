#!/usr/bin/env bash
# Boots the given iOS Simulator and puts it into the state the UI tests assume, so nothing about a
# fresh runner's simulator (first-launch costs, one-time system overlays) leaks into the first test.
#
# The status bar needs no pinning: the app hides it whenever it runs under a UI-test fixture.
#
# Usage: Scripts/simulator_prepare.sh <DEVICE> [APP_PATH]
#   DEVICE    simulator name, e.g. "iPhone 17" or "iPad (A16)"
#   APP_PATH  optional built Acai.app to install and launch once before the tests. On a cold CI
#             simulator the first launch took long enough to time out the first test ("Failed to
#             launch", "Timed out waiting for confirmation of orientation change").
set -euo pipefail

DEVICE="${1:?usage: Scripts/simulator_prepare.sh <DEVICE> [APP_PATH]}"
APP_PATH="${2:-}"
BUNDLE_ID="de.kraftsoftware.Acai"

# Device names can contain parens (e.g. "iPad (A16)"), so match everything before the fixed
# ` (UDID) (STATE)` suffix. `DEVICE_ENV` is exported rather than interpolated so parens stay literal.
export DEVICE_ENV="$DEVICE"
UDID=$(xcrun simctl list devices available | perl -ne '
    if (/^\s*(.+) \(([0-9A-Fa-f-]{36})\) \([A-Za-z]+\)\s*$/) {
        print "$2\n" if $1 eq $ENV{DEVICE_ENV};
    }
' | head -1)

if [ -z "$UDID" ]; then
    echo "✗ No available simulator named '$DEVICE' found" >&2
    exit 1
fi

echo "▸ Booting $DEVICE ($UDID) if needed"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b

# The keyboard's one-time "Slide to Type" overlay only renders the first time any keyboard appears,
# so whichever test happened to type first would capture it.
xcrun simctl spawn "$UDID" defaults write com.apple.keyboard.preferences \
    DidShowContinuousPathIntroduction -bool true

if [ -n "$APP_PATH" ]; then
    echo "▸ Warming up $BUNDLE_ID"
    xcrun simctl install "$UDID" "$APP_PATH"
    xcrun simctl launch "$UDID" "$BUNDLE_ID" > /dev/null
    sleep 10
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" || true
fi

echo "✓ $DEVICE ($UDID) prepared"
