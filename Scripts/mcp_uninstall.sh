#!/bin/zsh

# Uninstalls the Açaí MCP server binary installed by mcp_install.sh
#
# Usage:
#   ./Scripts/mcp_uninstall.sh [install-dir]
#
# If no install-dir is provided, common locations like /usr/local/bin and /opt/homebrew/bin are tried.

readonly MCP_NAME="acai-mcp"

# Determine candidate directories
CANDIDATES=()
if [[ -n "$1" ]]; then
  CANDIDATES+=("$1")
fi
CANDIDATES+=("/usr/local/bin" "/opt/homebrew/bin" "/usr/bin" "/usr/sbin")

TARGET=""
for dir in "${CANDIDATES[@]}"; do
  if [[ -f "$dir/$MCP_NAME" ]]; then
    TARGET="$dir/$MCP_NAME"
    break
  fi
done

# Also try resolving from PATH if no explicit dir found
if [[ -z "$TARGET" ]]; then
  if command -v "$MCP_NAME" >/dev/null 2>&1; then
    TARGET="$(command -v "$MCP_NAME")"
  fi
fi

if [[ -z "$TARGET" ]]; then
  print "ℹ️  '$MCP_NAME' not found in common locations. Nothing to uninstall."
  exit 0
fi

print "🧹 Uninstalling MCP server at $TARGET ..."
if rm -f "$TARGET" 2>/dev/null; then
  :
else
  sudo rm -f "$TARGET" || { print "❌ Failed to remove $TARGET"; exit 1; }
fi

print "✅ Uninstalled '$MCP_NAME'"
