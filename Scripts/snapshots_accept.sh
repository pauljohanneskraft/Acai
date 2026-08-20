#!/bin/bash
# Refreshes the committed XCUITest screenshot goldens from a CI run's uploaded captures.
#
# CI's renderer is the only one whose output the goldens are compared against, so a local recording
# run wouldn't produce trustworthy bytes — the artifacts are the source of truth. Every run uploads
# them (pass or fail), because ScreenshotComparator writes each capture unconditionally.
#
#   Scripts/snapshots_accept.sh            # newest Build & Test run for the current branch
#   Scripts/snapshots_accept.sh 32201788340
set -euo pipefail

cd "$(dirname "$0")/.."
GOLDENS="App/AcaiUITests/__Snapshots__"

RUN_ID="${1:-}"
if [ -z "$RUN_ID" ]; then
    BRANCH=$(git rev-parse --abbrev-ref HEAD)
    RUN_ID=$(gh run list --workflow build-test.yml --branch "$BRANCH" --limit 1 --json databaseId --jq '.[0].databaseId')
    [ -n "$RUN_ID" ] || { echo "No Build & Test run found for branch $BRANCH." >&2; exit 1; }
    echo "▸ Using newest Build & Test run for $BRANCH: $RUN_ID"
fi

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

FOUND=0
for PLATFORM in macOS iPhone iPad; do
    if gh run download "$RUN_ID" -n "$PLATFORM" -D "$STAGING/$PLATFORM" 2>/dev/null; then
        FOUND=1
    else
        echo "  ⚠️  no '$PLATFORM' artifact on run $RUN_ID — skipping"
        continue
    fi
    while IFS= read -r CAPTURE; do
        RELATIVE="${CAPTURE#"$STAGING/$PLATFORM/"}"
        TARGET="$GOLDENS/$PLATFORM/$RELATIVE"
        if cmp -s "$CAPTURE" "$TARGET"; then
            echo "  unchanged  $PLATFORM/$RELATIVE"
        else
            mkdir -p "$(dirname "$TARGET")"
            cp "$CAPTURE" "$TARGET"
            echo "  updated    $PLATFORM/$RELATIVE"
        fi
    done < <(find "$STAGING/$PLATFORM" -name '*.png')
done

[ "$FOUND" -eq 1 ] || { echo "No screenshot artifacts on run $RUN_ID." >&2; exit 1; }
echo "▸ Review with 'git diff -- $GOLDENS' before committing."
