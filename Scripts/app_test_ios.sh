#!/usr/bin/env bash
# Regenerates the Xcode project and runs the iOS UI test target (the snapshot tests), mirroring the
# CI job. Full xcodebuild output goes to LOG_PATH (huge and noisy); stdout stays to a concise
# pass/fail summary.
#
# Usage: Scripts/app_test_ios.sh [DEVICE] [ONLY_TESTING]
#   DEVICE        simulator name for -destination        (default: iPhone 17)
#   ONLY_TESTING  passed as -only-testing:<value> to scope to one class/test, e.g.
#                 Acai-iOSUITests/GitHubAddCodebaseTests   (default: run everything)
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEVICE="${1:-iPhone 17}"
ONLY_TESTING="${2:-}"
LOG_PATH="/tmp/acai-app-test-ios.log"

"$SCRIPT_DIR/simulator_prepare.sh" "$DEVICE"

cd "$SCRIPT_DIR/../App" || exit 1

echo "▸ xcodegen generate"
xcodegen generate --spec project.yml > "$LOG_PATH" 2>&1
if [ $? -ne 0 ]; then
    echo "✗ xcodegen generate failed:"; tail -40 "$LOG_PATH"; exit 1
fi

ONLY_ARGS=()
[ -n "$ONLY_TESTING" ] && ONLY_ARGS=("-only-testing:$ONLY_TESTING")

echo "▸ xcodebuild test -scheme Acai-iOSUITests -destination platform=iOS Simulator,name=$DEVICE ${ONLY_TESTING:+(only: $ONLY_TESTING)} (log: $LOG_PATH)"
# Parallel here but not in CI: simulator clones halve the wall time on a developer Mac, while on a
# CI runner they make each test several times slower and start failing app launches outright.
xcodebuild test \
    -project Acai.xcodeproj \
    -scheme Acai-iOSUITests \
    -destination "platform=iOS Simulator,name=$DEVICE" \
    -parallel-testing-enabled YES \
    -maximum-parallel-testing-workers 3 \
    CODE_SIGNING_ALLOWED=NO \
    "${ONLY_ARGS[@]}" \
    > "$LOG_PATH" 2>&1
STATUS=$?

echo "── Result summary ──"
grep -E "Test Suite '.*' (passed|failed)|error:|Executed .* tests?, with .* failures?" "$LOG_PATH" | tail -60

if [ $STATUS -eq 0 ]; then
    echo "✓ iOS UI tests passed (full log: $LOG_PATH)"
else
    echo "✗ iOS UI tests failed (full log: $LOG_PATH)"
fi
exit $STATUS
