#!/usr/bin/env bash
# The "before a change is done" gate from CLAUDE.md, as one command: build, full test suite,
# strict lint. Stops at the first failure.
#
# Usage: Scripts/verify.sh
set -euo pipefail

echo "▸ swift build"
swift build

echo "▸ swift test --parallel"
swift test --parallel

echo "▸ swiftlint lint --strict"
swiftlint lint --strict

echo "✓ verify passed"
