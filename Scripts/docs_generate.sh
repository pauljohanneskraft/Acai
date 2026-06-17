#!/bin/zsh

# Generates the DocC documentation site for all UML modules, ready for static
# hosting on GitHub Pages.
#
# Usage:
#   ./Scripts/docs_generate.sh [output-dir]
#
# If no output-dir is provided, the site is written to .build/docs. The output is
# transformed for static hosting under the "/UML/" base path (the GitHub Pages repo
# path) and a top-level index.html redirects to the friendly landing page so the
# site root lands somewhere welcoming.

# --- CONFIGURATION ---
readonly HOSTING_BASE_PATH="UML"
readonly LANDING_PATH="documentation/umllibrary"
# Every documentable module. UMLRender is macOS-only and UMLApp is a GUI executable
# with no public API, so the app is intentionally omitted.
readonly TARGETS=(
    UMLCore
    UMLTreeSitter
    UMLSwift
    UMLJVM
    UMLJS
    UMLDart
    UMLDiagram
    UMLLibrary
    UMLRender
)
# ---------------------

OUTPUT_DIR="${1:-.build/docs}"

# Build the repeated --target flags from the TARGETS array.
target_flags=()
for target in "${TARGETS[@]}"; do
    target_flags+=(--target "$target")
done

print "📚 Generating DocC site for ${#TARGETS[@]} modules into $OUTPUT_DIR ..."

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
# https://<owner>.github.io/$HOSTING_BASE_PATH/ open on UMLLibrary's overview
# regardless of what the combined-documentation root chooses to show.
print "🧭 Writing root redirect → $LANDING_PATH ..."
cat > "$OUTPUT_DIR/index.html" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta http-equiv="refresh" content="0; url=./$LANDING_PATH/">
    <link rel="canonical" href="./$LANDING_PATH/">
    <title>UML Documentation</title>
</head>
<body>
    <p>Redirecting to the <a href="./$LANDING_PATH/">UML documentation</a>…</p>
</body>
</html>
EOF

print "✅ Done. Site written to $OUTPUT_DIR"
print "▶️  Preview locally:  (cd $OUTPUT_DIR && python3 -m http.server 8000)  then open"
print "    http://localhost:8000/$LANDING_PATH/"
