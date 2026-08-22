#!/bin/zsh

# Generates the DocC documentation site for all Açaí modules, ready for static
# hosting on GitHub Pages.
#
# Usage:
#   ./Scripts/docs_generate.sh [output-dir]
#
# If no output-dir is provided, the site is written to .build/docs. The output is
# transformed for static hosting under the "/Acai/" base path (the GitHub Pages repo
# path) and a top-level index.html redirects to the friendly landing page so the
# site root lands somewhere welcoming.

# --- CONFIGURATION ---
readonly HOSTING_BASE_PATH="Acai"
readonly LANDING_PATH="documentation/acailibrary"
# ---------------------

OUTPUT_DIR="${1:-.build/docs}"

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

print "📚 Generating DocC site for ${#TARGETS[@]} modules into $OUTPUT_DIR ..."
print "   ${TARGETS[*]}"

if ! swift package --allow-writing-to-directory "$OUTPUT_DIR" \
    generate-documentation \
    --enable-experimental-combined-documentation \
    --output-path "$OUTPUT_DIR" \
    --transform-for-static-hosting \
    --hosting-base-path "$HOSTING_BASE_PATH" \
    "${target_flags[@]}"; then
    print "❌ Documentation generation failed."
    exit 1
fi

# 🧭 Redirect the site root to the friendly landing page. This makes
# https://<owner>.github.io/$HOSTING_BASE_PATH/ open on AcaiLibrary's overview
# regardless of what the combined-documentation root chooses to show.
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
