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

LAYER="${1:?usage: Scripts/snapshots_record.sh <layer1|ios|macos> [DEVICE]}"
DEVICE="${2:-iPhone 17}"
LOG_PATH="/tmp/acai-snapshots-record-$LAYER.log"

case "$LAYER" in
    layer1)
        echo "▸ ACAI_RECORD_SNAPSHOTS=1 swift test --parallel --filter AppScreenSnapshotTests (log: $LOG_PATH)"
        ACAI_RECORD_SNAPSHOTS=1 swift test --parallel --filter AppScreenSnapshotTests > "$LOG_PATH" 2>&1
        STATUS=$?
        ;;
    ios)
        cd "$(dirname "$0")/../App" || exit 1
        echo "▸ xcodegen generate"
        xcodegen generate --spec project.yml > "$LOG_PATH" 2>&1
        echo "▸ xcodebuild test -scheme Acai-iOSUITests ACAI_RECORD_SNAPSHOTS=1 (log: $LOG_PATH)"
        xcodebuild test \
            -project Acai.xcodeproj \
            -scheme Acai-iOSUITests \
            -destination "platform=iOS Simulator,name=$DEVICE" \
            CODE_SIGNING_ALLOWED=NO ACAI_RECORD_SNAPSHOTS=1 \
            > "$LOG_PATH" 2>&1
        STATUS=$?
        ;;
    macos)
        cd "$(dirname "$0")/../App" || exit 1
        echo "▸ xcodegen generate"
        xcodegen generate --spec project.yml > "$LOG_PATH" 2>&1
        echo "▸ xcodebuild test -scheme Acai-macOSUITests ACAI_RECORD_SNAPSHOTS=1 (log: $LOG_PATH)"
        xcodebuild test \
            -project Acai.xcodeproj \
            -scheme Acai-macOSUITests \
            -destination "platform=macOS" \
            CODE_SIGNING_ALLOWED=NO ACAI_RECORD_SNAPSHOTS=1 \
            > "$LOG_PATH" 2>&1
        STATUS=$?
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
