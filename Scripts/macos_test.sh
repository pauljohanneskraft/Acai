#!/usr/bin/env bash
# Regenerates the Xcode project and builds the macOS UI test target (Layer 2,
# TESTING_ARCHITECTURE.md). Defaults to build-for-testing only: unlike the iOS simulator, there's
# no simulator for macOS, so an actual `xcodebuild test` run drives real windows/mouse/keyboard on
# this Mac. Pass --run to opt into that explicitly.
#
# Usage: Scripts/macos_test.sh [--run]
set -euo pipefail

ACTION="build-for-testing"
[ "${1:-}" = "--run" ] && ACTION="test"

cd "$(dirname "$0")/../App"

echo "▸ xcodegen generate"
xcodegen generate --spec project.yml

echo "▸ xcodebuild $ACTION -scheme Acai-macOSUITests -destination platform=macOS"
xcodebuild "$ACTION" \
    -project Acai.xcodeproj \
    -scheme Acai-macOSUITests \
    -destination "platform=macOS" \
    CODE_SIGNING_ALLOWED=NO

echo "✓ macOS UI test target ($ACTION) succeeded"
