#!/usr/bin/env bash
# Copies snapshot-test screenshots staged by ScreenshotComparator's recording fallback into
# /private/tmp/AcaiUITestSnapshots/ — the same fixed, entitled location `ScreenshotComparator`
# writes recordings to directly on macOS (see its own `outputDirectory` doc comment). This fallback
# only matters if even that direct write unexpectedly fails: `NSTemporaryDirectory()` inside the
# sandboxed macOS UI test runner resolves to the runner's own container tmp dir, not this shell's
# plain $TMPDIR, so the staged output has to be located inside the container. Mirrors
# `outputDirectory`'s own `<platform>/<viewType>/<state>` layout, so once found this is a plain
# recursive copy, no per-file renaming needed.
#
# Usage: Scripts/sync_ui_snapshots.sh
set -uo pipefail

DEST="/private/tmp/AcaiUITestSnapshots"

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

if [ "$STAGING" = "$DEST" ]; then
    echo "Staged snapshots already at $DEST — nothing to sync."
    exit 0
fi

echo "▸ Syncing staged snapshots:"
find "$STAGING" -name '*.png' -print | while read -r FILE; do
    echo "  ${FILE#"$STAGING"/}"
done

mkdir -p "$DEST"
cp -R "$STAGING/." "$DEST/"
rm -rf "$STAGING"

echo "✓ Synced into $DEST — copy these over App/AcaiUITests/__Snapshots__/<platform>/ and review the diffed PNGs before committing."
