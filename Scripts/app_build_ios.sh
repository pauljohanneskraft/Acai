#!/usr/bin/env bash
# Regenerates the Xcode project and builds the iOS app target for the Simulator, mirroring the CI
# `build-ios` job — useful as a quick cross-platform build check without running any tests.
#
# Usage: Scripts/app_build_ios.sh
set -euo pipefail

cd "$(dirname "$0")/../App"

echo "▸ xcodegen generate"
xcodegen generate --spec project.yml

echo "▸ xcodebuild build -scheme Acai-iOS -destination generic/platform=iOS Simulator"
xcodebuild build \
    -project Acai.xcodeproj \
    -scheme Acai-iOS \
    -destination "generic/platform=iOS Simulator" \
    CODE_SIGNING_ALLOWED=NO

echo "✓ iOS Simulator build succeeded"
