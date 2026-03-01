#!/bin/zsh

# Uninstalls the CLI binary installed by install_cli.sh
#
# Usage:
#   ./uninstall_cli.sh [install-dir]
#
# If no install-dir is provided, the script will attempt common locations
# like /usr/local/bin and /opt/homebrew/bin.

readonly CLI_NAME="uml"

# Determine candidate directories
CANDIDATES=()
if [[ -n "$1" ]]; then
  CANDIDATES+=("$1")
fi
CANDIDATES+=("/usr/local/bin" "/opt/homebrew/bin" "/usr/bin" "/usr/sbin")

TARGET=""
for dir in "${CANDIDATES[@]}"; do
  if [[ -f "$dir/$CLI_NAME" ]]; then
    TARGET="$dir/$CLI_NAME"
    break
  fi
done

# Also try resolving from PATH if no explicit dir found
if [[ -z "$TARGET" ]]; then
  if command -v "$CLI_NAME" >/dev/null 2>&1; then
    TARGET="$(command -v "$CLI_NAME")"
  fi
fi

if [[ -z "$TARGET" ]]; then
  print "ℹ️  '$CLI_NAME' not found in common locations. Nothing to uninstall."
  exit 0
fi

print "🧹 Uninstalling CLI at $TARGET ..."
if rm -f "$TARGET" 2>/dev/null; then
  :
else
  sudo rm -f "$TARGET" || { print "❌ Failed to remove $TARGET"; exit 1; }
fi

print "✅ Uninstalled '$CLI_NAME'"
