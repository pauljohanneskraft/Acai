#!/bin/zsh

# Builds the Açaí MCP server for release and stages the stripped binary in .build/artifacts.
# Mirrors cli_create.sh — the MCP server is a third entry point over the same engine, so it ships
# the same way the CLI does. The release pipeline (release.yml) uses this to assemble per-platform
# archives; a developer can also run it directly before mcp_install.sh.

# --- CONFIGURATION ---
readonly MCP_TARGET="AcaiMCP"
readonly MCP_NAME="acai-mcp"
readonly ARTIFACTS_DIR=".build/artifacts"
# ---------------------

# 1. Build the MCP server for Release
print "🚀 Building $MCP_TARGET for Release..."
if ! swift build -c release --arch arm64 --product "$MCP_TARGET"; then
    print "❌ Build failed."
    exit 1
fi

# 2. Prepare artifacts directory
mkdir -p "$ARTIFACTS_DIR"

# 3. Copy and rename the binary into the artifacts dir (next to the CLI + app bundle)
readonly SOURCE_BIN=".build/release/$MCP_TARGET"
readonly DEST_BIN="$ARTIFACTS_DIR/$MCP_NAME"

if [ ! -f "$SOURCE_BIN" ]; then
    print "❌ Expected binary not found at $SOURCE_BIN"
    exit 1
fi

rm -f "$DEST_BIN"
cp "$SOURCE_BIN" "$DEST_BIN"
chmod +x "$DEST_BIN"

# 4. Strip symbols to reduce size (safe for release binaries)
if command -v strip >/dev/null 2>&1; then
    strip -x "$DEST_BIN" 2>/dev/null || true
fi

print "✅ Success! The Açaí MCP server is ready at $(dirs -p | head -1)/$DEST_BIN"
