#!/bin/zsh

# --- CONFIGURATION ---
readonly CLI_TARGET="AcaiCLI"
readonly CLI_NAME="acai"
readonly ARTIFACTS_DIR=".build/artifacts"
# ---------------------

# 1. Build CLI for Release
print "🚀 Building $CLI_TARGET for Release..."
if ! swift build -c release --arch arm64 --product "$CLI_TARGET"; then
    print "❌ Build failed."
    exit 1
fi

# 2. Prepare artifacts directory
mkdir -p "$ARTIFACTS_DIR"

# 3. Copy and rename binary into artifacts dir (next to the app bundle)
readonly SOURCE_BIN=".build/release/$CLI_TARGET"
readonly DEST_BIN="$ARTIFACTS_DIR/$CLI_NAME"

if [ ! -f "$SOURCE_BIN" ]; then
    print "❌ Expected binary not found at $SOURCE_BIN"
    exit 1
fi

rm -f "$DEST_BIN"
cp "$SOURCE_BIN" "$DEST_BIN"
chmod +x "$DEST_BIN"

# 4. Optionally strip symbols to reduce size (safe for release binaries)
if command -v strip >/dev/null 2>&1; then
    strip -x "$DEST_BIN" 2>/dev/null || true
fi

print "✅ Success! Your CLI is ready at $(dirs -p | head -1)/$DEST_BIN"
