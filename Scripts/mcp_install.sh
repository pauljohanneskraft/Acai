#!/bin/zsh

# Builds and installs the MCP server binary.
#
# Usage:
#   ./Scripts/mcp_install.sh [install-dir]
#
# If no install-dir is provided, installs to ~/.local/bin (creating it if needed).
# After installing, register the binary in your Claude Code MCP settings.

set -euo pipefail

readonly MCP_NAME="uml-mcp"
readonly REPO_ROOT="${0:a:h:h}"

# Determine destination directory
INSTALL_DIR="${1:-$HOME/.local/bin}"

print "🔧 Building MCP server '$MCP_NAME' (release) ..."
cd "$REPO_ROOT"
swift build -c release --product UMLMCP 2>&1 | tail -5

# Locate the built binary
BUILD_BIN="$(swift build -c release --product UMLMCP --show-bin-path)/UMLMCP"
if [[ ! -f "$BUILD_BIN" ]]; then
  print "❌ Build artifact not found at $BUILD_BIN"
  exit 1
fi

# Ensure destination directory exists
if [[ ! -d "$INSTALL_DIR" ]]; then
  print "📁 Creating directory $INSTALL_DIR ..."
  mkdir -p "$INSTALL_DIR"
fi

DEST="$INSTALL_DIR/$MCP_NAME"

# Copy the binary
cp "$BUILD_BIN" "$DEST"
chmod +x "$DEST"

# Optionally strip symbols to reduce size
if command -v strip >/dev/null 2>&1; then
  strip -x "$DEST" 2>/dev/null || true
fi

# PATH hint
case ":$PATH:" in
  *":$INSTALL_DIR:"*) IN_PATH=1 ;;
  *) IN_PATH=0 ;;
esac

print "✅ Installed: $DEST"
if [[ $IN_PATH -eq 0 ]]; then
  print "⚠️  Note: $INSTALL_DIR is not in your PATH."
  print "   Add it to your shell profile or reference the binary by absolute path in MCP settings."
fi

print ""
print "📋 Register in Claude Code (claude_desktop_config.json or .claude/settings.json):"
print ""
print "  \"mcpServers\": {"
print "    \"uml\": {"
print "      \"command\": \"$DEST\""
print "    }"
print "  }"
