#!/bin/bash
# Prints the test identifiers shard <index> of <count> runs (1-based), one per line, taken from the
# JSON `xcodebuild -enumerate-tests -test-enumeration-style flat -test-enumeration-format json`
# writes. Every enumerated test lands in exactly one shard, so a new journey needs no registration.
#
#   Scripts/ui_test_shard.sh 2 4 ui-tests.json
set -euo pipefail

INDEX="$1"
COUNT="$2"
ENUMERATION="$3"

# A runner that fails to launch still writes JSON, with the error recorded and only the target listed.
ERRORS=$(jq -r '.errors[]' "$ENUMERATION")
if [ -n "$ERRORS" ]; then
    echo "✗ Test enumeration failed:" >&2
    echo "$ERRORS" >&2
    exit 1
fi

# Target/Class/method only: an abstract base class such as UIJourneyTestCase is listed without a method.
TESTS=$(jq -r '.values[].enabledTests[].identifier' "$ENUMERATION" | awk -F/ 'NF == 3' | sort)
if [ -z "$TESTS" ]; then
    echo "✗ Test enumeration listed no tests." >&2
    exit 1
fi

awk -v shard="$INDEX" -v count="$COUNT" '(NR - 1) % count == shard - 1' <<< "$TESTS"
