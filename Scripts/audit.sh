#!/usr/bin/env bash
# Deterministic code-quality audit: composes the uml CLI primitives into one report bundle.
#
# The tool stays a set of deterministic commands; this script is just the "combination" — it analyzes
# the source ONCE, then fans every other command out against that stored artifact (--from) so each
# command reuses the same snapshot instead of re-parsing. Interpretation of the outputs is the
# operator's job (read report/ and the diagrams); nothing here calls an LLM.
#
# Usage: Scripts/audit.sh [SOURCE_DIR] [OUTPUT_DIR] [RULES_YAML]
#   SOURCE_DIR  directory to analyze            (default: .)
#   OUTPUT_DIR  where the bundle is written     (default: ./audit-report)
#   RULES_YAML  quality rules for the gate      (default: quality.yml if present, else default budgets)
set -euo pipefail

SOURCE_DIR="${1:-.}"
OUT_DIR="${2:-./audit-report}"
RULES="${3:-quality.yml}"

# Prefer an installed `uml`; fall back to a debug build of this repo.
UML="$(command -v uml || true)"
[ -z "$UML" ] && UML="$(dirname "$0")/../.build/debug/UMLCLI"

mkdir -p "$OUT_DIR"
ARTIFACT="$OUT_DIR/artifact.json"

echo "▸ analyze (one pass) → $ARTIFACT"
"$UML" analyze --source "$SOURCE_DIR" --output "$ARTIFACT"

echo "▸ metrics (json + human)"
"$UML" metrics --from "$ARTIFACT" --output "$OUT_DIR/metrics.json"
"$UML" metrics --from "$ARTIFACT" --format human --sort weightedMethods --top 25 \
    --output "$OUT_DIR/metrics.txt"

echo "▸ quality explore (ranked smells + dependency cycles, no gate)"
"$UML" quality --from "$ARTIFACT" --explore --scope all --format json --output "$OUT_DIR/quality-explore.json"

echo "▸ call graph (metrics + method cycles + dead code)"
"$UML" callgraph --from "$ARTIFACT" --mode metrics --output "$OUT_DIR/callgraph.json"
"$UML" callgraph --from "$ARTIFACT" --mode cycles --no-fail --output "$OUT_DIR/call-cycles.json"
"$UML" callgraph --from "$ARTIFACT" --mode deadcode --output "$OUT_DIR/deadcode.json"

echo "▸ parse health"
"$UML" analyze --from "$ARTIFACT" --health --output "$OUT_DIR/health.json"

echo "▸ type + member inventory (+ enum inventory)"
"$UML" inspect --from "$ARTIFACT" --output "$OUT_DIR/inspect.json"
"$UML" inspect --from "$ARTIFACT" --enums --output "$OUT_DIR/enums.json"

echo "▸ package diagram (dot)"
"$UML" diagram --from "$ARTIFACT" --package --format dot --output "$OUT_DIR/package.dot"

# Quality gate. With a rules file it gates on that; otherwise the built-in curated smell budgets.
# Non-zero exit is preserved so CI can gate on it.
CHECK_STATUS=0
if [ -f "$RULES" ]; then
    echo "▸ quality gate against $RULES"
    "$UML" quality --from "$ARTIFACT" --rules "$RULES" --format json --explore \
        --output "$OUT_DIR/quality.json"
    "$UML" quality --from "$ARTIFACT" --rules "$RULES" >/dev/null 2>&1 || CHECK_STATUS=$?
else
    echo "▸ quality gate against built-in smell budgets"
    "$UML" quality --from "$ARTIFACT" --format json --explore --output "$OUT_DIR/quality.json"
    "$UML" quality --from "$ARTIFACT" >/dev/null 2>&1 || CHECK_STATUS=$?
fi

# PNGs are macOS-only (the image command links UMLRender there).
if [ "$(uname)" = "Darwin" ]; then
    echo "▸ images (package + class PNG)"
    "$UML" image --from "$ARTIFACT" --package --output "$OUT_DIR/package.png" || true
    "$UML" image --from "$ARTIFACT" --output "$OUT_DIR/class.png" || true
fi

echo "✓ audit bundle written to $OUT_DIR"
exit "$CHECK_STATUS"
