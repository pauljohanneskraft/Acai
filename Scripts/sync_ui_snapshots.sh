#!/usr/bin/env bash
# Copies snapshot-test screenshot goldens staged by ScreenshotComparator's recording fallback into
# App/AcaiUITests/__Snapshots__/.
#
# The macOS UI test runner is sandboxed by default, so it fails writing into the source tree with
# EPERM, and `NSTemporaryDirectory()` inside it resolves to the container's own tmp dir, not this
# shell's plain $TMPDIR — so the staged output has to be located inside the container. It mirrors
# __Snapshots__/'s own `<platform>/<viewType>/<state>` layout, so once found this is a plain
# recursive copy, no per-file renaming needed.
#
# Usage: Scripts/sync_ui_snapshots.sh
set -uo pipefail

DEST="$(cd "$(dirname "$0")/../App/AcaiUITests/__Snapshots__" 2>/dev/null && pwd || echo "$(dirname "$0")/../App/AcaiUITests/__Snapshots__")"

# Try the plain (unsandboxed) location first — this is what a non-sandboxed host (or iOS
# Simulator, though that already writes directly and never needs this script) would use — then
# fall back to searching every UI-test-runner container for the sandboxed macOS case.
STAGING="${TMPDIR:-/tmp}/AcaiUITestSnapshots"
if [ ! -d "$STAGING" ]; then
    STAGING="$(find "$HOME/Library/Containers" -maxdepth 5 -type d -name AcaiUITestSnapshots -print 2>/dev/null | head -1)"
fi

if [ -z "$STAGING" ] || [ ! -d "$STAGING" ]; then
    echo "No staged snapshots found (checked \$TMPDIR and ~/Library/Containers/*/Data/tmp) — nothing to sync."
    exit 0
fi

echo "▸ Syncing staged snapshots:"
find "$STAGING" -name '*.png' -print | while read -r FILE; do
    echo "  ${FILE#"$STAGING"/}"
done

mkdir -p "$DEST"
cp -R "$STAGING/." "$DEST/"
rm -rf "$STAGING"

echo "✓ Synced into $DEST — review the diffed PNGs (git status / open the files) before committing."
