#!/usr/bin/env bash
# Boots the given iOS Simulator (if needed) and pins its status bar (time, battery, signal) to
# fixed values, so screenshot goldens don't churn on the wall-clock digits alone.
#
# `simctl status_bar override` is the only way to pin the status bar — `Process`/`NSTask` isn't
# available on iOS at all, so this can't be called from inside the Swift UI test code itself and
# instead runs as a normal step before `xcodebuild test`.
#
# Known limitation: `--time` only pins the clock, not the date (confirmed via `simctl status_bar
# <udid> list`, which never shows a date field regardless of input format). Only iPad's landscape
# status bar shows a date at all, so this is a narrow residual source of golden churn.
#
# `simctl` converts `--time` from UTC to the *host Mac's* local timezone for display — not the
# simulator's, and not affected by the invoking process's `TZ` env var. A fixed UTC string would
# therefore display differently per host timezone, so instead we compute the UTC instant
# corresponding to "today at 9:41 local time" and pass that.
#
# Usage: Scripts/simulator_prepare.sh <DEVICE>
#   DEVICE  simulator name, e.g. "iPhone 17" or "iPad (A16)"
set -euo pipefail

DEVICE="${1:?usage: Scripts/simulator_prepare.sh <DEVICE>}"

# Device names can contain parens themselves (e.g. "iPad (A16)"), so match everything before the
# fixed ` (UDID) (STATE)` suffix rather than splitting per paren group. `DEVICE_ENV` is exported
# (not interpolated into the pattern) so parens in the name are literal, not regex metacharacters.
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

echo "▸ Booting $DEVICE ($UDID) if needed and pinning its status bar"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b

# The keyboard's one-time "Slide to Type" tutorial overlay (real device and simulator alike) only
# renders the *first* time any keyboard appears on it — whichever run happens to be that first use
# gets it baked into its screenshot goldens, and no later run can reproduce it on demand. Suppressing
# it here, before any test touches a text field, keeps every recording deterministic.
xcrun simctl spawn "$UDID" defaults write com.apple.keyboard.preferences \
    DidShowContinuousPathIntroduction -bool true

# Two-step local→epoch→UTC conversion: passing `-u` alongside `-j -f` would make BSD `date` treat
# the *input* string as UTC too, silently skipping the timezone conversion. Routing through an
# epoch (timezone-agnostic by construction) avoids that.
TODAY_LOCAL_0941_EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "$(date +%Y-%m-%d) 09:41:00" "+%s")
PINNED_TIME=$(date -u -r "$TODAY_LOCAL_0941_EPOCH" "+%Y-%m-%dT%H:%M:%S.000Z")

# `simctl` rejects an ISO date-time with no fractional seconds ("Invalid, non-ISO date/time
# string") but accepts one with milliseconds included.
xcrun simctl status_bar "$UDID" override \
    --time "$PINNED_TIME" \
    --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --batteryState charged --batteryLevel 100

echo "✓ $DEVICE ($UDID) status bar pinned"
