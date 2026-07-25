#!/usr/bin/env bash
# Boots the given iOS Simulator (if needed) and gets it into a clean, reproducible state before a
# UI test run — currently just pinning its status bar (time, battery, signal) to fixed values, so
# Layer 2 screenshot goldens (TESTING_ARCHITECTURE.md) don't churn on the wall-clock digits alone
# across re-recordings or CI runs. Named for "prepare the simulator" generally, not
# `simulator_pin_status_bar.sh`, since more such preparation may land here later.
#
# `simctl status_bar override` is the only way to pin the status bar — there's no way to call it
# from inside the Swift UI test code itself: `Process`/`NSTask` isn't available on iOS at all (a
# compile-time exclusion from the SDK, not just a runtime restriction), even though the UI test
# bundle runs inside the simulator. So this runs as a normal step before `xcodebuild test`, the same
# way `xcodegen generate` already does — not a manual step a person has to remember, just not
# literally inside the Swift test process.
#
# **Known limitation, accepted rather than worked around**: `--time` only pins the clock, not the
# date — confirmed via `simctl status_bar <udid> list`, which shows just a `Time:` field, no date,
# regardless of whether `--time` is given a plain clock string or a full ISO date-time (despite
# `simctl`'s own help text claiming the latter "will also set the date on relevant devices"). Only
# iPad's landscape status bar shows a date at all (iPhone and portrait iPad don't), so this is a
# narrow, low-impact residual source of golden churn, not a systemic one.
#
# `--time` requires a full ISO date-time (a bare "9:41" is accepted too, but see below), and
# `simctl` converts it from UTC to the *host Mac's* local timezone for display — not the
# simulator's, and not the invoking process's `TZ` env var (confirmed empirically: neither
# `simctl spawn <udid> launchctl setenv TZ ...` nor `TZ=UTC xcrun simctl ...` changed the displayed
# time). So a fixed UTC string would display differently depending on which timezone the host
# happens to be in — CI runners and different contributors' Macs would each show a different time,
# still churning goldens. Instead, compute the UTC instant that corresponds to "today at 9:41 *local
# time*" and pass that, so the displayed time is always exactly 9:41 regardless of host timezone.
#
# Usage: Scripts/simulator_prepare.sh <DEVICE>
#   DEVICE  simulator name, e.g. "iPhone 17" or "iPad (A16)"
set -euo pipefail

DEVICE="${1:?usage: Scripts/simulator_prepare.sh <DEVICE>}"

# The device name itself can contain parentheses (e.g. "iPad (A16)"), so a naive per-paren-group
# split misparses `simctl list devices`' `<name> (<udid>) (<state>)` text output — greedily capture
# everything before the fixed ` (UDID) (STATE)` suffix instead, via `DEVICE_ENV` (exported, not
# interpolated into the pattern) so parens in the name are plain characters to match, not regex
# metacharacters.
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

# Two-step local→epoch→UTC conversion (not a one-line `date -u -j -f ... -u ...`): passing `-u`
# alongside `-j -f` makes BSD `date` treat the *input* string as UTC too, silently skipping the
# actual timezone conversion — confirmed empirically (the "converted" value came back unchanged).
# Routing through an epoch (timezone-agnostic by construction) avoids that trap.
TODAY_LOCAL_0941_EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "$(date +%Y-%m-%d) 09:41:00" "+%s")
PINNED_TIME=$(date -u -r "$TODAY_LOCAL_0941_EPOCH" "+%Y-%m-%dT%H:%M:%S.000Z")

# `simctl`'s ISO date-time parser is stricter than it looks: it rejects a plain "yyyy-MM-
# dd'T'HH:mm:ssZ" (no fractional seconds) with "Invalid, non-ISO date/time string" — confirmed
# empirically by trying several RFC 3339-valid variants — but accepts the same string with
# milliseconds included.
xcrun simctl status_bar "$UDID" override \
    --time "$PINNED_TIME" \
    --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --batteryState charged --batteryLevel 100

echo "✓ $DEVICE ($UDID) status bar pinned"
