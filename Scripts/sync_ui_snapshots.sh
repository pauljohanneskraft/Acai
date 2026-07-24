#!/usr/bin/env bash
# Copies Layer 2 screenshot goldens staged by ScreenshotComparator's recording fallback
# (TESTING_ARCHITECTURE.md) into App/AcaiUITests/__Snapshots__/.
#
# Needed because the macOS UI test runner is sandboxed by default (confirmed empirically: its
# process resolves under ~/Library/Containers/de.kraftsoftware.Acai.UITests.xctrunner/, despite no
# .entitlements file in the project — this is an Xcode/xctrunner default, not something the app
# opts into) and fails writing into the source tree with EPERM even with Full Disk Access granted.
# `NSTemporaryDirectory()` inside that sandboxed process resolves to the container's own tmp dir,
# NOT this shell's plain $TMPDIR — so ScreenshotComparator's staged output has to be located inside
# the container, not assumed to sit at a fixed top-level path. ScreenshotComparator stages each
# recorded PNG under .../AcaiUITestSnapshots/<viewType>/<platform>/<state> — the exact same
# relative layout as __Snapshots__/ itself — so once found, this is a plain recursive copy, no
# per-file renaming logic needed.
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
