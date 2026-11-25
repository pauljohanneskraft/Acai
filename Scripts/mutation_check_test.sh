#!/bin/bash
# Runs Scripts/mutation_check.sh against a throwaway package whose diff holds one hunk no test sees,
# one a test catches, and one that stops the tests compiling, then checks it classified all three.
#
#   Scripts/mutation_check_test.sh
set -euo pipefail

CHECK="$(cd "$(dirname "$0")" && pwd)/mutation_check.sh"

# A caller filtering changed paths on this list must see the module the fixture below mutates.
if ! "$CHECK" --paths | grep -qx "Sources/AcaiCore"; then
    echo "✗ --paths does not list Sources/AcaiCore." >&2
    exit 1
fi

FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "$FIXTURE/Sources/AcaiCore" "$FIXTURE/Tests/AcaiCoreTests"
cd "$FIXTURE"

cat > Package.swift <<'EOF'
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Fixture",
    targets: [
        .target(name: "AcaiCore"),
        .testTarget(name: "AcaiCoreTests", dependencies: ["AcaiCore"]),
    ]
)
EOF

# No test reads `text`, so reverting it survives.
cat > Sources/AcaiCore/Label.swift <<'EOF'
public struct Label {
    public var text: String { "counter" }
}
EOF

# A test asserts the sum, so reverting it is caught.
cat > Sources/AcaiCore/Total.swift <<'EOF'
public struct Total {
    public let values: [Int]

    public init(values: [Int]) { self.values = values }

    public var sum: Int { values.first ?? 0 }
}
EOF

# The test suite names `Reading`, so reverting its rename stops the tests compiling.
cat > Sources/AcaiCore/Dimension.swift <<'EOF'
public struct Metric {
    public init() {}

    public var millimetres: Int { 12 }
}
EOF

cat > Tests/AcaiCoreTests/TotalTests.swift <<'EOF'
import Testing
import AcaiCore

@Test func totalOfOne() { #expect(Total(values: [4]).sum == 4) }
EOF

git init --quiet .
git config user.email fixture@example.com
git config user.name Fixture
git add .
git commit --quiet -m "Base"
BASE=$(git rev-parse HEAD)

sed -i 's/"counter"/"tally"/' Sources/AcaiCore/Label.swift
sed -i 's/values.first ?? 0/values.reduce(0, +)/' Sources/AcaiCore/Total.swift
sed -i 's/struct Metric/struct Reading/' Sources/AcaiCore/Dimension.swift
cat >> Tests/AcaiCoreTests/TotalTests.swift <<'EOF'

@Test func totalOfThree() { #expect(Total(values: [1, 2, 3]).sum == 6) }

@Test func readingInMillimetres() { #expect(Reading().millimetres == 12) }
EOF
git add .
git commit --quiet -m "Change three things"

REPORT=$("$CHECK" "$BASE")
echo "$REPORT"

FAILURES=0
expect() {
    if ! grep -qE "$1" <<< "$REPORT"; then
        echo "✗ Report has no match for: $1" >&2
        FAILURES=$((FAILURES + 1))
    fi
}
reject() {
    if grep -qE "$1" <<< "$REPORT"; then
        echo "✗ Report should not match: $1" >&2
        FAILURES=$((FAILURES + 1))
    fi
}

expect '^3 hunk\(s\) against .*: 1 caught, 1 surviving, 1 not applicable, 0 not reached\.$'
expect '^- `Sources/AcaiCore/Label\.swift:[0-9]'
expect '^- Sources/AcaiCore/Dimension\.swift:[0-9-]+ — does not compile on its own$'
reject '^- `?Sources/AcaiCore/Total\.swift'

# The fixture's own checkout is untouched, and the script left no worktree behind.
if [ -n "$(git status --porcelain)" ]; then
    echo "✗ The script modified the working tree." >&2
    FAILURES=$((FAILURES + 1))
fi
if [ "$(git worktree list | wc -l)" -ne 1 ]; then
    echo "✗ The script left a worktree behind." >&2
    FAILURES=$((FAILURES + 1))
fi

# Out of time is its own outcome: no hunk may be read as caught because the clock ran out.
BUDGET=$(MUTATION_CHECK_TIME_LIMIT=1 "$CHECK" "$BASE")
if ! grep -qE '^3 hunk\(s\) against .*: 0 caught, 0 surviving, 0 not applicable, 3 not reached\.$' \
    <<< "$BUDGET"; then
    echo "✗ A one-second budget did not report all three hunks as not reached:" >&2
    echo "$BUDGET" >&2
    FAILURES=$((FAILURES + 1))
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "✗ $FAILURES check(s) failed." >&2
    exit 1
fi
echo "✓ mutation_check.sh classified all three hunks."
