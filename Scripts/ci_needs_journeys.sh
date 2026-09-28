#!/bin/bash
# Reads changed paths (one per line) on stdin and prints `true` unless every one of them is outside
# what the UI journeys exercise. Journeys only parse Swift for real — every other analysis comes from
# canned fixtures — so the non-Swift plugins, the CLI/MCP binaries, unit tests and prose can't change
# a journey's outcome. Anything not listed here runs the journeys, as does an empty diff.
#
#   git diff --name-only origin/main...HEAD | Scripts/ci_needs_journeys.sh
set -euo pipefail

JOURNEY_INDEPENDENT='^(Sources/(AcaiJS|AcaiJVM|AcaiDart|AcaiPython|CPythonScanner|AcaiCFamily|AcaiCLI|AcaiMCP)/'
JOURNEY_INDEPENDENT+='|Tests/|Examples/|Formula/|Guides\.docc/|\.claude/|\.claude-plugin/|\.github/images/'
JOURNEY_INDEPENDENT+='|[^ ]*\.docc/|README\.md$|CLAUDE\.md$|LICENSE$|action\.yml$|\.codecov\.yml$|\.swiftlint\.yml$'
JOURNEY_INDEPENDENT+='|\.github/copilot-instructions\.md$)'

CHANGED=$(grep -v '^$' || true)
if [ -z "$CHANGED" ] || grep -qvE "$JOURNEY_INDEPENDENT" <<< "$CHANGED"; then
    echo true
else
    echo false
fi
