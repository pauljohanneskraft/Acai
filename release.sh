#!/bin/zsh

# --- CONFIGURATION ---
readonly APP_NAME="UMLApp"
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
echo "📦 Creating $APP_BUNDLE..."

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

echo "🎨 Converting Assets to .icns..."
mkdir -p "Temporary.iconset"
cp "$ICONSET_PATH"/*.png "Temporary.iconset/"
LARGEST_PNG=$(ls -S "$ICONSET_PATH"/*.png | head -n 1)
sips -z 1024 1024 "$LARGEST_PNG" --out "Temporary.iconset/icon_512x512@2x.png"
sips -z 512 512 "$LARGEST_PNG" --out "Temporary.iconset/icon_512x512.png"
sips -z 256 256 "$LARGEST_PNG" --out "Temporary.iconset/icon_256x256.png"
sips -z 128 128 "$LARGEST_PNG" --out "Temporary.iconset/icon_128x128.png"
iconutil -c icns "Temporary.iconset" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
rm -rf "Temporary.iconset"

cp ".build/release/$EXECUTABLE_TARGET" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$INFO_PLIST_PATH" "$APP_BUNDLE/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon.icns" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $APP_NAME" "$APP_BUNDLE/Contents/Info.plist"

echo "✍️ Ad-hoc signing..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "✅ Success! Your app is ready at $(pwd)/$APP_BUNDLE"
