#!/usr/bin/env bash
# Re-records committed snapshot goldens for one test suite.
#
# ACAI_RECORD_SNAPSHOTS: the render snapshot tests (SwiftPM) read it as a normal env var; the
# snapshot tests (XCUITest) only see it as a trailing xcodebuild build-setting override — a plain
# shell export never reaches the Xcode-launched test process.
#
# The `render` layer's SnapshotComparator writes straight into the committed goldens — review
# `git status`/the diffed PNGs before committing. The `ios`/`macos` layers never touch the
# committed goldens directly; they write to a separate output path (printed below on success) for
# manual copy-over instead — see `AcaiUITests/Support/ScreenshotComparator.swift`'s `outputDirectory`.
#
# Full xcodebuild/swift test output goes to LOG_PATH; stdout stays to a concise summary.
#
# Usage: Scripts/snapshots_record.sh <render|ios|macos> [DEVICE]
#   DEVICE  simulator name for the ios layer's -destination   (default: iPhone 17)
set -uo pipefail

# Captured before any `cd` below — a path built from a bare `$0` breaks once the working directory
# changes.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

LAYER="${1:?usage: Scripts/snapshots_record.sh <render|ios|macos> [DEVICE]}"
DEVICE="${2:-iPhone 17}"
LOG_PATH="/tmp/acai-snapshots-record-$LAYER.log"

# Scoped to the tests that actually call ScreenshotComparator.validate — this script records
# goldens, it isn't a general-purpose "run the UI suite" entry point. Add a test class here in the
# same change that gives it its first comparator.validate call.
SCREENSHOT_TESTS=(
    ScreenshotJourneyTests CompareGitRevisionTests
    NewSheetsScreenshotTests GeneratedDiagramScreenshotTests
)

case "$LAYER" in
    render)
        echo "▸ ACAI_RECORD_SNAPSHOTS=1 swift test --parallel --filter AppScreenSnapshotTests (log: $LOG_PATH)"
        ACAI_RECORD_SNAPSHOTS=1 swift test --parallel --filter AppScreenSnapshotTests > "$LOG_PATH" 2>&1
        STATUS=$?
        # This layer's own SnapshotComparator (Tests/AcaiAppTests/ViewSnapshot.swift, unrelated to
        # AcaiUITests/Support/ScreenshotComparator.swift) writes straight into the committed goldens
        # — always was, unaffected by the XCUITest layers' recording-output redirection below.
        OUTPUT_PATH=""
        ;;
    ios)
        "$SCRIPT_DIR/simulator_prepare.sh" "$DEVICE"
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
        # ScreenshotComparator never writes into __Snapshots__/ itself — recordings land in a
        # sibling __RecordedSnapshots__/ directory (see its own `outputDirectory` doc comment);
        # copy over just the states that actually changed.
        OUTPUT_PATH="$SCRIPT_DIR/../App/AcaiUITests/__RecordedSnapshots__"
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
        # ScreenshotComparator writes recordings directly to /private/tmp/AcaiUITestSnapshots on
        # macOS (an entitled, non-container path — see its own `outputDirectory` doc comment), so
        # this should just work with no sync step. If that direct write ever unexpectedly fails
        # (staged inside the sandboxed runner's own container instead, reported as a failure in
        # $LOG_PATH), run Scripts/sync_ui_snapshots.sh manually to recover it.
        OUTPUT_PATH="/private/tmp/AcaiUITestSnapshots"
        ;;
    *)
        echo "unknown layer: $LAYER (expected render, ios, or macos)" >&2
        exit 1
        ;;
esac

echo "── Result summary ──"
grep -E "Test Suite '.*' (passed|failed)|error:|Executed .* tests?, with .* failures?" "$LOG_PATH" | tail -60

if [ "$STATUS" -eq 0 ]; then
    if [ -n "$OUTPUT_PATH" ]; then
        echo "✓ recorded to $OUTPUT_PATH — copy the changed files over the matching"
        echo "  App/AcaiUITests/__Snapshots__/<platform>/ folder, then review git status/the diffed PNGs before committing."
    else
        echo "✓ recorded. Review git status and the diffed PNGs before committing new goldens. (full log: $LOG_PATH)"
    fi
else
    echo "✗ recording run failed (full log: $LOG_PATH)"
fi
exit "$STATUS"
