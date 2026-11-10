#!/usr/bin/env bash
# Renders a generated class diagram with `acai image` and fails when its peak resident memory exceeds the budget.
#
# Usage: Scripts/ci_render_memory_budget.sh <path-to-acai-binary> [budget-MB]
set -euo pipefail

ACAI="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
# Debug build peaks at ~1,930 MB; without the autorelease pools ~2,125+ MB, without the area cap ~2,260+ MB.
BUDGET_MB="${2:-2050}"
CHAINS=36
DEPTH=33
TYPES=$((CHAINS * DEPTH))

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/Sources"
echo "public class Root {}" > "$WORK/Sources/Root.swift"

# Deterministic fixture: side-by-side inheritance chains under one root, so the diagram is square and
# large enough that the pixel-area ceiling, not the per-dimension one, sets the scale.
for ((chain = 0; chain < CHAINS; chain++)); do
    {
        for ((level = 0; level < DEPTH; level++)); do
            if ((level == 0)); then
                echo "public class C${chain}L0: Root {"
            else
                echo "public class C${chain}L${level}: C${chain}L$((level - 1)) {"
            fi
            for ((member = 0; member < 6; member++)); do
                echo "    public var property$member: C${chain}L$(((level + member + 2) % DEPTH))?"
            done
            for ((member = 0; member < 4; member++)); do
                echo "    public func method$member(argument: Int) -> String { \"\" }"
            done
            echo "}"
        done
    } > "$WORK/Sources/Chain$chain.swift"
done

# An instrumented (coverage) binary writes its profile into the working directory on exit.
STATUS=0
STATS=$(cd "$WORK" && LLVM_PROFILE_FILE=/dev/null /usr/bin/time -l "$ACAI" image \
    --source "$WORK/Sources" --language swift --output "$WORK/diagram.png" 2>&1 >/dev/null) || STATUS=$?
PEAK_BYTES=$(awk '/maximum resident set size/ { print $1 }' <<< "$STATS")
if [ "$STATUS" -ne 0 ] || [ -z "$PEAK_BYTES" ] || [ ! -s "$WORK/diagram.png" ]; then
    echo "$STATS"
    echo "::error::acai image did not render the memory-budget fixture"
    exit 1
fi
PEAK_MB=$((PEAK_BYTES / 1024 / 1024))

echo "acai image peaked at ${PEAK_MB} MB resident (budget ${BUDGET_MB} MB) for ${TYPES} generated types"
if ((PEAK_MB > BUDGET_MB)); then
    echo "::error::acai image peaked at ${PEAK_MB} MB, over its ${BUDGET_MB} MB budget"
    exit 1
fi
