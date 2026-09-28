#!/usr/bin/env bash
# Resolves, boots and warms the iOS Simulator the UI tests run on, and prints its UDID.
#
# A runner image carries the same device name on more than one runtime, so a `name=` destination is
# ambiguous: this script's pick and xcodebuild's pick were different devices, leaving every
# xcodebuild run to cold-boot an unwarmed simulator — 7 to 15 silent minutes before the first test.
# The runtime is therefore pinned to the simulator SDK, and every xcodebuild destination from here
# on names the resolved UDID (exported as SIM_UDID under GitHub Actions) rather than the device.
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

SDK_VERSION=$(xcrun --sdk iphonesimulator --show-sdk-version)
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-${SDK_VERSION//./-}"

UDID=$(xcrun simctl list devices available -j | jq -r \
    --arg runtime "$RUNTIME" --arg name "$DEVICE" \
    '.devices[$runtime] // [] | map(select(.name == $name)) | .[0].udid // empty')

if [ -z "$UDID" ]; then
    echo "✗ No available simulator named '$DEVICE' on $RUNTIME" >&2
    xcrun simctl list devices available >&2
    exit 1
fi

echo "▸ Booting $DEVICE on iOS $SDK_VERSION ($UDID) if needed"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b

# The keyboard's one-time "Slide to Type" overlay only renders the first time any keyboard appears,
# so whichever test happened to type first would capture it. Prediction and autocorrection go with
# it: the QuickType bar's suggestions are per-run content in any screenshot that has the keyboard up.
xcrun simctl spawn "$UDID" defaults write com.apple.keyboard.preferences \
    DidShowContinuousPathIntroduction -bool true
xcrun simctl spawn "$UDID" defaults write com.apple.keyboard.preferences \
    KeyboardPrediction -bool false
xcrun simctl spawn "$UDID" defaults write com.apple.keyboard.preferences \
    KeyboardAutocorrection -bool false

if [ -n "$APP_PATH" ]; then
    echo "▸ Warming up $BUNDLE_ID"
    xcrun simctl install "$UDID" "$APP_PATH"
    xcrun simctl launch "$UDID" "$BUNDLE_ID" > /dev/null
    sleep 10
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" || true
fi

if [ -n "${GITHUB_ENV:-}" ]; then
    echo "SIM_UDID=$UDID" >> "$GITHUB_ENV"
fi

echo "✓ $DEVICE ($UDID) prepared"
