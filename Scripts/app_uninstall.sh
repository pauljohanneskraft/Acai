#!/bin/zsh

# Uninstalls the macOS app bundle installed by install_app.sh
#
# Usage:
#   ./uninstall_app.sh [install-dir]
#
# If no install-dir is provided, defaults to /Applications.

readonly APP_NAME="UML.app"

DEST_DIR="$1"
if [[ -z "$DEST_DIR" ]]; then
  DEST_DIR="/Applications"
fi

DEST_APP="$DEST_DIR/$APP_NAME"

if [[ ! -d "$DEST_APP" ]]; then
  print "ℹ️  $DEST_APP not found. Nothing to uninstall."
  exit 0
fi

print "🧹 Uninstalling app at $DEST_APP ..."
if rm -rf "$DEST_APP" 2>/dev/null; then
  :
else
  sudo rm -rf "$DEST_APP" || { print "❌ Failed to remove $DEST_APP"; exit 1; }
fi

print "✅ Uninstalled $APP_NAME"
