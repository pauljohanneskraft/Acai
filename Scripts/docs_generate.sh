#!/bin/zsh

# Generates the DocC documentation site for all Açaí modules, ready for static
# hosting on GitHub Pages.
#
# Usage:
#   ./Scripts/docs_generate.sh [output-dir]
#
# If no output-dir is provided, the site is written to .build/docs. The output is
# transformed for static hosting under the "/Acai/" base path (the GitHub Pages repo
# path) and a top-level index.html redirects to the combined landing page.

# --- CONFIGURATION ---
readonly HOSTING_BASE_PATH="Acai"
readonly LANDING_PATH="documentation"
# The prose catalog: articles only, no target and no code. `docc convert` accepts a
# catalog with no symbol graphs, so it becomes an archive like any module's.
readonly GUIDES_CATALOG="Guides.docc"
# ---------------------

OUTPUT_DIR="${1:-.build/docs}"

DOCC="$(xcrun --find docc 2>/dev/null)"
if [[ -z "$DOCC" ]]; then
    print "❌ Could not locate 'docc'. This script requires an Xcode toolchain."
    exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
readonly ARCHIVES_DIR="$WORK_DIR/archives"

# Every non-test target in the manifest, read from the package itself so a newly added
# module is documented without touching this script. Test targets are the only exclusion:
# DocC handles library, executable and C targets alike (an executable renders as a
# "Command-line Tool"), and a target with no public API simply yields an empty page —
# which is still better than having no page at all.
#
# Platform-conditional targets (AcaiRender, AcaiApp, AcaiGit, AcaiPNGComparison, gated on
# `canImport(SwiftUI)` in Package.swift) appear here only when the manifest compiles on a
# SwiftUI-capable host — the docs workflow runs on macOS, so they are included there.
TARGETS=("${(@f)$(swift package dump-package | python3 -c '
import json, sys
for target in json.load(sys.stdin)["targets"]:
    if target["type"] != "test":
        print(target["name"])
')}")

if [[ ${#TARGETS[@]} -eq 0 ]]; then
    print "❌ Could not read any targets from the package manifest."
    exit 1
fi

# Build the repeated --target flags from the TARGETS array.
target_flags=()
for target in "${TARGETS[@]}"; do
    target_flags+=(--target "$target")
done

print "📚 Generating DocC archives for ${#TARGETS[@]} modules ..."
print "   ${TARGETS[*]}"

# 1️⃣ One archive per target. Deliberately not `--enable-experimental-combined-documentation`:
# that merges the archives itself, in task-completion order, which makes the navigator's
# order both non-alphabetical and unstable between runs. Merging by hand below fixes both
# and is the only way to include a catalog that belongs to no target.
if ! swift package --allow-writing-to-directory "$ARCHIVES_DIR" \
    generate-documentation \
    --output-path "$ARCHIVES_DIR" \
    "${target_flags[@]}"; then
    print "❌ Documentation generation failed."
    exit 1
fi

# 2️⃣ The prose archive, built straight from the catalog.
print "📝 Building $GUIDES_CATALOG ..."
if ! "$DOCC" convert "$GUIDES_CATALOG" --output-path "$ARCHIVES_DIR/Guides.doccarchive"; then
    print "❌ Building $GUIDES_CATALOG failed."
    exit 1
fi

# 3️⃣ Merge, guides first and the modules alphabetically after them. This argument order is
# exactly the navigator's order. (The landing page's own card grid is sorted by DocC on the
# page title, which is why the guides page is titled to sort ahead of the modules.)
archive_paths=("$ARCHIVES_DIR/Guides.doccarchive")
for archive in "${(@f)$(print -l "$ARCHIVES_DIR"/*.doccarchive | sort)}"; do
    [[ "$archive" == "$ARCHIVES_DIR/Guides.doccarchive" ]] && continue
    archive_paths+=("$archive")
done

if [[ ${#archive_paths[@]} -le 1 ]]; then
    print "❌ No module archives were produced."
    exit 1
fi

print "🧩 Merging ${#archive_paths[@]} archives ..."
if ! "$DOCC" merge "${archive_paths[@]}" \
    --synthesized-landing-page-name "Acai" \
    --synthesized-landing-page-kind "Package" \
    --synthesized-landing-page-topics-style detailedGrid \
    --output-path "$WORK_DIR/Acai.doccarchive"; then
    print "❌ Merging the documentation archives failed."
    exit 1
fi

# 4️⃣ Lay the merged archive out for a static host under "/$HOSTING_BASE_PATH/".
print "🌐 Transforming for static hosting under /$HOSTING_BASE_PATH/ ..."
rm -rf "$OUTPUT_DIR"
if ! "$DOCC" process-archive transform-for-static-hosting "$WORK_DIR/Acai.doccarchive" \
    --output-path "$OUTPUT_DIR" \
    --hosting-base-path "$HOSTING_BASE_PATH"; then
    print "❌ Transforming the archive for static hosting failed."
    exit 1
fi

# 🧭 Redirect the site root to the combined landing page. That page is the only entry point
# whose sidebar lists every module: the renderer scopes the navigator once, from the URL the
# visitor arrives on, so landing on any single module's page would hide the rest.
print "🧭 Writing root redirect → $LANDING_PATH ..."
cat > "$OUTPUT_DIR/index.html" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta http-equiv="refresh" content="0; url=./$LANDING_PATH/">
    <link rel="canonical" href="./$LANDING_PATH/">
    <title>Açaí Documentation</title>
</head>
<body>
    <p>Redirecting to the <a href="./$LANDING_PATH/">Açaí documentation</a>…</p>
</body>
</html>
EOF

print "✅ Done. Site written to $OUTPUT_DIR"
print "▶️  Preview locally:  (cd $OUTPUT_DIR && python3 -m http.server 8000)  then open"
print "    http://localhost:8000/$LANDING_PATH/"
