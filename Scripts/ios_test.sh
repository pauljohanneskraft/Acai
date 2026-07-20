#!/usr/bin/env bash
# Regenerates the Xcode project and runs the iOS UI test target (Layer 2, TESTING_ARCHITECTURE.md),
# mirroring the CI `test-ios-ui` job.
#
# Usage: Scripts/ios_test.sh [DEVICE]
#   DEVICE  simulator name for -destination   (default: iPhone 17)
set -euo pipefail

DEVICE="${1:-iPhone 17}"

cd "$(dirname "$0")/../App"

echo "▸ xcodegen generate"
xcodegen generate --spec project.yml

echo "▸ xcodebuild test -scheme Acai-iOSUITests -destination platform=iOS Simulator,name=$DEVICE"
xcodebuild test \
    -project Acai.xcodeproj \
    -scheme Acai-iOSUITests \
    -destination "platform=iOS Simulator,name=$DEVICE" \
    CODE_SIGNING_ALLOWED=NO

echo "✓ iOS UI tests passed"
