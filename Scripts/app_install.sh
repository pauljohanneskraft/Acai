#!/bin/zsh

# Installs the macOS app bundle built by release.sh into Applications.
#
# Usage:
#   ./install_app.sh [destination-dir]
#
# If no destination is provided, defaults to /Applications.
# It will prompt for sudo if necessary.

readonly APP_NAME="UML.app"
readonly SOURCE_APP_DIR=".build/artifacts/$APP_NAME"

DEST_DIR="$1"
if [[ -z "$DEST_DIR" ]]; then
  DEST_DIR="/Applications"
fi

print "📦 Installing app '$APP_NAME' to $DEST_DIR ..."

# Ensure source exists
if [[ ! -d "$SOURCE_APP_DIR" ]]; then
  print "❌ App bundle not found at $SOURCE_APP_DIR"
  print "   Build it first with: ./release.sh"
  exit 1
fi

# Ensure destination directory exists
if [[ ! -d "$DEST_DIR" ]]; then
  print "📁 Creating directory $DEST_DIR ..."
  if mkdir -p "$DEST_DIR" 2>/dev/null; then
    :
  else
    sudo mkdir -p "$DEST_DIR" || { print "❌ Failed to create $DEST_DIR"; exit 1; }
  fi
fi

DEST_APP="$DEST_DIR/$APP_NAME"

# If an app already exists, remove it first
if [[ -d "$DEST_APP" ]]; then
  print "♻️  Replacing existing $DEST_APP ..."
  if rm -rf "$DEST_APP" 2>/dev/null; then
    :
  else
    sudo rm -rf "$DEST_APP" || { print "❌ Failed to remove existing $DEST_APP"; exit 1; }
  fi
fi

# Copy the app bundle
if cp -R "$SOURCE_APP_DIR" "$DEST_APP" 2>/dev/null; then
  :
else
  sudo cp -R "$SOURCE_APP_DIR" "$DEST_APP" || { print "❌ Failed to copy app to $DEST_APP"; exit 1; }
fi

print "✅ Installed: $DEST_APP"
