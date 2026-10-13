#!/bin/bash
# Turns the `.drift` files ScreenshotComparator writes beside every capture into a table on the CI
# job summary, so a red run names what moved and by how much without anyone downloading an artifact.
# Reads files rather than the build log: neither stdout nor XCTActivity survives a
# `-parallel-testing-enabled` run's console output.
set -uo pipefail

cd "$(dirname "$0")/.."
OUT="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

# Wherever the comparator's `outputDirectory` resolved to on this platform.
ROOTS=("/private/tmp/AcaiUITestSnapshots" "App/AcaiUITests/__RecordedSnapshots__" "Tests/AcaiWidgetTests/__RecordedSnapshots__")

# Each `.drift` line plus its root, where that state's `.captured.png` would be; one row per state.
DRIFTS=$(for ROOT in "${ROOTS[@]}"; do
    [ -d "$ROOT" ] || continue
    while IFS= read -r FILE; do
        LINE=$(cat "$FILE")
        [ -n "$LINE" ] && printf '%s %s\n' "$LINE" "$ROOT"
    done < <(find "$ROOT" -name '*.drift')
done | sort -u -k1,1)

if [ -z "$DRIFTS" ]; then
    echo "No screenshot comparisons ran." >> "$OUT"
    exit 0
fi

{
    echo "### Screenshot drift"
    echo
    echo "| State | Drift | Threshold | |"
    echo "|---|---:|---:|---|"
    echo "$DRIFTS" | while read -r NAME DRIFT THRESHOLD CELLS ROOT; do
        if awk -v d="$DRIFT" -v t="$THRESHOLD" 'BEGIN { exit !(d > t) }'; then
            VERDICT="❌ over"
        elif [ -f "$ROOT/$NAME.captured.png" ]; then
            VERDICT="ok — capture differs, kept as \`$NAME.captured.png\`"
        else
            VERDICT="ok"
        fi
        printf '| `%s` | %s%% (%s cells) | %s%% | %s |\n' "$NAME" "$DRIFT" "$CELLS" "$THRESHOLD" "$VERDICT"
    done
    echo
    echo "Refresh goldens with \`Scripts/snapshots_accept.sh\` once the change is intentional."
    echo
    echo "A state under its threshold uploads the committed golden's own bytes as \`<state>.png\`, so"
    echo "that file matching the golden says nothing about the run. Where the capture differed it is"
    echo "uploaded beside it as \`<state>.captured.png\` — that one is the run's real pixels."
} >> "$OUT"
