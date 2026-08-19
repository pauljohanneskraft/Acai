#!/bin/bash
# Turns the `.drift` files ScreenshotComparator writes beside every capture into a table on the CI
# job summary, so a red run names what moved and by how much without anyone downloading an artifact.
# Reads files rather than the build log: neither stdout nor XCTActivity survives a
# `-parallel-testing-enabled` run's console output.
set -uo pipefail

cd "$(dirname "$0")/.."
OUT="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

# Wherever the comparator's `outputDirectory` resolved to on this platform.
ROOTS=("/private/tmp/AcaiUITestSnapshots" "App/AcaiUITests/__RecordedSnapshots__")

DRIFTS=$(for ROOT in "${ROOTS[@]}"; do
    [ -d "$ROOT" ] && find "$ROOT" -name '*.drift' -exec cat {} \; -exec echo \;
done | grep -v '^$' | sort -u)

if [ -z "$DRIFTS" ]; then
    echo "No screenshot comparisons ran." >> "$OUT"
    exit 0
fi

{
    echo "### Screenshot drift"
    echo
    echo "| State | Drift | Threshold | |"
    echo "|---|---:|---:|---|"
    echo "$DRIFTS" | while read -r NAME DRIFT THRESHOLD CELLS; do
        VERDICT=$(awk -v d="$DRIFT" -v t="$THRESHOLD" 'BEGIN { print (d <= t) ? "ok" : "❌ over" }')
        printf '| `%s` | %s%% (%s cells) | %s%% | %s |\n' "$NAME" "$DRIFT" "$CELLS" "$THRESHOLD" "$VERDICT"
    done
    echo
    echo "Refresh goldens with \`Scripts/snapshots_accept.sh\` once the change is intentional."
} >> "$OUT"
