#!/usr/bin/env bash
# Regenerates the Xcode project and runs the iOS UI test target (Layer 2, TESTING_ARCHITECTURE.md),
# mirroring the CI `test-ios-ui` job. Full xcodebuild output goes to LOG_PATH (huge and noisy);
# stdout stays to a concise pass/fail summary, so this script alone (no ad hoc `> file` redirection
# at the call site) is enough to both run and triage — avoiding a fresh permission prompt per
# differently-redirected invocation.
#
# Usage: Scripts/app_test_ios.sh [DEVICE] [ONLY_TESTING]
#   DEVICE        simulator name for -destination        (default: iPhone 17)
#   ONLY_TESTING  passed as -only-testing:<value> to scope to one class/test, e.g.
#                 Acai-iOSUITests/GitHubAddCodebaseTests   (default: run everything)
set -o pipefail

DEVICE="${1:-iPhone 17}"
ONLY_TESTING="${2:-}"
LOG_PATH="/tmp/acai-app-test-ios.log"

cd "$(dirname "$0")/../App" || exit 1

echo "▸ xcodegen generate"
xcodegen generate --spec project.yml > "$LOG_PATH" 2>&1
if [ $? -ne 0 ]; then
    echo "✗ xcodegen generate failed:"; tail -40 "$LOG_PATH"; exit 1
fi

ONLY_ARGS=()
[ -n "$ONLY_TESTING" ] && ONLY_ARGS=("-only-testing:$ONLY_TESTING")

echo "▸ xcodebuild test -scheme Acai-iOSUITests -destination platform=iOS Simulator,name=$DEVICE ${ONLY_TESTING:+(only: $ONLY_TESTING)} (log: $LOG_PATH)"
xcodebuild test \
    -project Acai.xcodeproj \
    -scheme Acai-iOSUITests \
    -destination "platform=iOS Simulator,name=$DEVICE" \
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
