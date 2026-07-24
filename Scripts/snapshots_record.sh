#!/usr/bin/env bash
# Re-records committed snapshot goldens for one testing layer (TESTING_ARCHITECTURE.md).
#
# Encodes the ACAI_RECORD_SNAPSHOTS propagation gotcha found while building the testing system:
# Layer 1 (SwiftPM) reads it as a normal env var; Layer 2 (XCUITest) only sees it as a *trailing*
# xcodebuild build-setting override, never a leading shell `export` — a plain shell export never
# reaches the Xcode-launched test process.
#
# Recording silently overwrites goldens — review `git status`/the diffed PNGs before committing.
#
# Full xcodebuild/swift test output goes to LOG_PATH; stdout stays to a concise summary — no ad hoc
# `> file` redirection needed at the call site.
#
# Usage: Scripts/snapshots_record.sh <layer1|ios|macos> [DEVICE]
#   DEVICE  simulator name for the ios layer's -destination   (default: iPhone 17)
set -uo pipefail

# Captured before any `cd` below — a path built from a bare `$0` breaks the moment the working
# directory changes, which is exactly what silently swallowed the call to sync_ui_snapshots.sh
# the one time this was tried without it (it resolved relative to App/, not Scripts/).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

LAYER="${1:?usage: Scripts/snapshots_record.sh <layer1|ios|macos> [DEVICE]}"
DEVICE="${2:-iPhone 17}"
LOG_PATH="/tmp/acai-snapshots-record-$LAYER.log"

# Scoped to the tests that actually call ScreenshotComparator.validate — this script records
# goldens, it isn't a general-purpose "run the UI suite" entry point. Add a test class here in the
# same change that gives it its first comparator.validate call.
SCREENSHOT_TESTS=(ScreenshotJourneyTests CompareGitRevisionTests)

case "$LAYER" in
    layer1)
        echo "▸ ACAI_RECORD_SNAPSHOTS=1 swift test --parallel --filter AppScreenSnapshotTests (log: $LOG_PATH)"
        ACAI_RECORD_SNAPSHOTS=1 swift test --parallel --filter AppScreenSnapshotTests > "$LOG_PATH" 2>&1
        STATUS=$?
        ;;
    ios)
        cd "$SCRIPT_DIR/../App" || exit 1
        echo "▸ xcodegen generate"
        xcodegen generate --spec project.yml > "$LOG_PATH" 2>&1
        ONLY_TESTING=()
        for T in "${SCREENSHOT_TESTS[@]}"; do ONLY_TESTING+=("-only-testing:Acai-iOSUITests/$T"); done
        echo "▸ xcodebuild test -scheme Acai-iOSUITests ACAI_RECORD_SNAPSHOTS=1 (log: $LOG_PATH)"
        xcodebuild test \
            -project Acai.xcodeproj \
            -scheme Acai-iOSUITests \
            -destination "platform=iOS Simulator,name=$DEVICE" \
            "${ONLY_TESTING[@]}" \
            CODE_SIGNING_ALLOWED=NO ACAI_RECORD_SNAPSHOTS=1 \
            > "$LOG_PATH" 2>&1
        STATUS=$?
        ;;
    macos)
        cd "$SCRIPT_DIR/../App" || exit 1
        echo "▸ xcodegen generate"
        xcodegen generate --spec project.yml > "$LOG_PATH" 2>&1
        ONLY_TESTING=()
        for T in "${SCREENSHOT_TESTS[@]}"; do ONLY_TESTING+=("-only-testing:Acai-macOSUITests/$T"); done
        echo "▸ xcodebuild test -scheme Acai-macOSUITests ACAI_RECORD_SNAPSHOTS=1 (log: $LOG_PATH)"
        echo "  (this drives real windows/mouse/keyboard on this Mac — step away until it's done,"
        echo "  and close any always-on-top overlays like Picture-in-Picture video first: they"
        echo "  float above every window and will bleed into the captured screenshot)"
        # Ad-hoc signing, not CODE_SIGNING_ALLOWED=NO: a real macOS binary needs at least a
        # signature to launch on Apple Silicon at all, or the OS kills it with "app is damaged".
        xcodebuild test \
            -project Acai.xcodeproj \
            -scheme Acai-macOSUITests \
            -destination "platform=macOS" \
            "${ONLY_TESTING[@]}" \
            CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM="" \
            ACAI_RECORD_SNAPSHOTS=1 \
            > "$LOG_PATH" 2>&1
        STATUS=$?
        # The macOS UI test runner is sandboxed by default (its own ~/Library/Containers/...
        # container) and has been observed to refuse writing goldens directly into the source
        # tree (EPERM) even with Full Disk Access granted — ScreenshotComparator stages those
        # inside its container's tmp dir instead, so sync them in regardless of $STATUS.
        "$SCRIPT_DIR/sync_ui_snapshots.sh"
        ;;
    *)
        echo "unknown layer: $LAYER (expected layer1, ios, or macos)" >&2
        exit 1
        ;;
esac

echo "── Result summary ──"
grep -E "Test Suite '.*' (passed|failed)|error:|Executed .* tests?, with .* failures?" "$LOG_PATH" | tail -60

if [ "$STATUS" -eq 0 ]; then
    echo "✓ recorded. Review git status and the diffed PNGs before committing new goldens. (full log: $LOG_PATH)"
else
    echo "✗ recording run failed (full log: $LOG_PATH)"
fi
exit "$STATUS"
