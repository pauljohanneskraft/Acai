#!/bin/zsh

# --- CONFIGURATION ---
readonly APP_NAME="UML"
readonly INFO_PLIST_PATH="./Sources/UMLApp/Resources/Info.plist"
readonly BUNDLE_ID="de.pauljohanneskraft.uml"
readonly EXECUTABLE_TARGET="UMLApp"
readonly ICONSET_PATH="./Sources/UMLApp/Resources/Assets.xcassets/AppIcon.imageset"
# ---------------------

# 1. Clean and Build for Release
echo "🚀 Building $EXECUTABLE_TARGET for Release..."
swift build -c release --arch arm64

if [ $? -ne 0 ]; then
    echo "❌ Build failed."
    exit 1
fi

# 2. Setup Bundle Structure
readonly APP_BUNDLE="$APP_NAME.app"
readonly APP_BUNDLE_DIR=".build/artifacts/$APP_NAME.app"
echo "📦 Creating $APP_BUNDLE..."

rm -rf "$APP_BUNDLE_DIR"
mkdir -p "$APP_BUNDLE_DIR/Contents/MacOS"
mkdir -p "$APP_BUNDLE_DIR/Contents/Resources"

echo "🎨 Converting Assets to .icns..."
readonly TEMP_ICONSET="$APP_BUNDLE_DIR/Temporary.iconset"
mkdir -p "$TEMP_ICONSET"
cp "$ICONSET_PATH"/*.png "$TEMP_ICONSET"
LARGEST_PNG=$(ls -S "$ICONSET_PATH"/*.png | head -n 1)
sips -z 1024 1024 "$LARGEST_PNG" --out "$TEMP_ICONSET/icon_512x512@2x.png" > /dev/null
sips -z 512 512 "$LARGEST_PNG" --out "$TEMP_ICONSET/icon_512x512.png" > /dev/null
sips -z 256 256 "$LARGEST_PNG" --out "$TEMP_ICONSET/icon_256x256.png" > /dev/null
sips -z 128 128 "$LARGEST_PNG" --out "$TEMP_ICONSET/icon_128x128.png" > /dev/null
iconutil -c icns "$TEMP_ICONSET" -o "$APP_BUNDLE_DIR/Contents/Resources/AppIcon.icns"
rm -rf "$TEMP_ICONSET"

cp ".build/release/$EXECUTABLE_TARGET" "$APP_BUNDLE_DIR/Contents/MacOS/$EXECUTABLE_TARGET"
cp "$INFO_PLIST_PATH" "$APP_BUNDLE_DIR/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$APP_BUNDLE_DIR/Contents/Info.plist" 2>/dev/null
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon.icns" "$APP_BUNDLE_DIR/Contents/Info.plist"

echo "✅ Success! Your app is ready at $(dirs -p | head -1)/$APP_BUNDLE_DIR"
