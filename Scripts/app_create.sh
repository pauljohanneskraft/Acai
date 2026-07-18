#!/bin/zsh

# Builds the macOS app via the XcodeGen-generated Xcode project (App/project.yml) rather than a raw
# `swift build` + hand-assembled bundle — Xcode's own build system now handles Info.plist
# generation and app-icon compilation (from App/macOS/Assets.xcassets) natively, so the old
# iconutil/sips/PlistBuddy steps are no longer needed.

set -euo pipefail

# --- CONFIGURATION ---
readonly APP_NAME="Acai"
readonly SCHEME="Acai-macOS"
readonly PROJECT_DIR="App"
readonly DERIVED_DATA_DIR=".build/xcode-macos"
readonly APP_BUNDLE_DIR=".build/artifacts/$APP_NAME.app"
# ---------------------

echo "⚙️  Generating Xcode project..."
xcodegen generate --spec "$PROJECT_DIR/project.yml"

echo "🚀 Building $SCHEME for Release..."
xcodebuild \
    -project "$PROJECT_DIR/Acai.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    -destination "platform=macOS" \
    build \
    CODE_SIGNING_ALLOWED=NO

echo "📦 Staging $APP_NAME.app..."
rm -rf "$APP_BUNDLE_DIR"
mkdir -p "$(dirname "$APP_BUNDLE_DIR")"
cp -R "$DERIVED_DATA_DIR/Build/Products/Release/$APP_NAME.app" "$APP_BUNDLE_DIR"

echo "✅ Success! Your app is ready at $(dirs -p | head -1)/$APP_BUNDLE_DIR"
