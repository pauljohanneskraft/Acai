#!/bin/zsh

# Installs the UML MCP server binary built by mcp_create.sh into a system path.
#
# Usage:
#   ./Scripts/mcp_install.sh [install-dir]
#
# If no install-dir is provided, defaults to /usr/local/bin (or /opt/homebrew/bin if it exists).
# Prompts for sudo if needed. This is the build-from-source path; released binaries can instead be
# unpacked from a GitHub release archive.

readonly MCP_NAME="uml-mcp"
readonly SOURCE_BIN=".build/artifacts/$MCP_NAME"

# Determine destination directory
INSTALL_DIR="$1"
if [[ -z "$INSTALL_DIR" ]]; then
  if [[ -d "/usr/local/bin" ]]; then
    INSTALL_DIR="/usr/local/bin"
  elif [[ -d "/opt/homebrew/bin" ]]; then
    INSTALL_DIR="/opt/homebrew/bin"
  else
    INSTALL_DIR="/usr/local/bin"
  fi
fi

print "🔧 Installing MCP server '$MCP_NAME' to $INSTALL_DIR ..."

# Ensure source exists
if [[ ! -f "$SOURCE_BIN" ]]; then
  print "❌ Source binary not found at $SOURCE_BIN"
  print "   Build it first with: ./Scripts/mcp_create.sh"
  exit 1
fi

# Ensure destination directory exists
if [[ ! -d "$INSTALL_DIR" ]]; then
  print "📁 Creating directory $INSTALL_DIR ..."
  if mkdir -p "$INSTALL_DIR" 2>/dev/null; then
    :
  else
    sudo mkdir -p "$INSTALL_DIR" || { print "❌ Failed to create $INSTALL_DIR"; exit 1; }
  fi
fi

DEST="$INSTALL_DIR/$MCP_NAME"

# Copy the binary
if cp "$SOURCE_BIN" "$DEST" 2>/dev/null; then
  :
else
  sudo cp "$SOURCE_BIN" "$DEST" || { print "❌ Failed to copy to $DEST"; exit 1; }
fi

# Ensure executable bit
if chmod +x "$DEST" 2>/dev/null; then
  :
else
  sudo chmod +x "$DEST" || { print "❌ Failed to set executable bit on $DEST"; exit 1; }
fi

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
  print "⚠️  Note: $INSTALL_DIR is not in your PATH. Register '$DEST' directly in your MCP client config."
fi
