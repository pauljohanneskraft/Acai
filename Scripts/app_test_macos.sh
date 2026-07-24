#!/usr/bin/env bash
# Regenerates the Xcode project and builds the macOS UI test target (Layer 2,
# TESTING_ARCHITECTURE.md). Defaults to build-for-testing only: unlike the iOS simulator, there's
# no simulator for macOS, so an actual `xcodebuild test` run drives real windows/mouse/keyboard on
# this Mac. Pass --run to opt into that explicitly.
#
# Full xcodebuild output goes to LOG_PATH; stdout stays to a concise summary — no ad hoc `> file`
# redirection needed at the call site.
#
# Usage: Scripts/app_test_macos.sh [--run]
set -uo pipefail

ACTION="build-for-testing"
[ "${1:-}" = "--run" ] && ACTION="test"
LOG_PATH="/tmp/acai-app-test-macos.log"

cd "$(dirname "$0")/../App" || exit 1

echo "▸ xcodegen generate"
xcodegen generate --spec project.yml > "$LOG_PATH" 2>&1

echo "▸ xcodebuild $ACTION -scheme Acai-macOSUITests -destination platform=macOS (log: $LOG_PATH)"
# Unlike the iOS Simulator scripts, a real macOS binary needs at least an ad-hoc signature to
# launch at all on Apple Silicon — CODE_SIGNING_ALLOWED=NO makes the OS kill it on launch with
# "Acai.app is damaged and can't be opened" (verified empirically: AMFI rejects a fully unsigned
# Mach-O outright, it's not actual corruption). Ad-hoc signing needs no certificate/team.
xcodebuild "$ACTION" \
    -project Acai.xcodeproj \
    -scheme Acai-macOSUITests \
    -destination "platform=macOS" \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM="" \
    > "$LOG_PATH" 2>&1
STATUS=$?

echo "── Result summary ──"
grep -E "Test Suite '.*' (passed|failed)|error:|Executed .* tests?, with .* failures?|BUILD SUCCEEDED|BUILD FAILED" "$LOG_PATH" | tail -60

if [ $STATUS -eq 0 ]; then
    echo "✓ macOS UI test target ($ACTION) succeeded (full log: $LOG_PATH)"
else
    echo "✗ macOS UI test target ($ACTION) failed (full log: $LOG_PATH)"
fi
exit $STATUS
