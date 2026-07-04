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
#   RULES_YAML  conformance rules for check     (default: architecture.yml if present, else skipped)
set -euo pipefail

SOURCE_DIR="${1:-.}"
OUT_DIR="${2:-./audit-report}"
RULES="${3:-architecture.yml}"

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

echo "▸ cycles (modules + types)"
"$UML" cycles --from "$ARTIFACT" --scope all --format json --no-fail --output "$OUT_DIR/cycles.json"

echo "▸ smells (ranked)"
"$UML" smells --from "$ARTIFACT" --output "$OUT_DIR/smells.json"

echo "▸ dead-code candidates"
"$UML" deadcode --from "$ARTIFACT" --output "$OUT_DIR/deadcode.json"

echo "▸ call graph (metrics) + call cycles"
"$UML" callgraph --from "$ARTIFACT" --output "$OUT_DIR/callgraph.json"
"$UML" call-cycles --from "$ARTIFACT" --no-fail --output "$OUT_DIR/call-cycles.json"

echo "▸ parse health (doctor)"
"$UML" doctor --from "$ARTIFACT" --output "$OUT_DIR/doctor.json"

echo "▸ type + member inventory"
"$UML" inspect --from "$ARTIFACT" --output "$OUT_DIR/inspect.json"

echo "▸ package diagram (dot)"
"$UML" diagram --from "$ARTIFACT" --package --format dot --output "$OUT_DIR/package.dot"

# Conformance check (only if a rules file exists). Non-zero exit is preserved so CI can gate on it.
CHECK_STATUS=0
if [ -f "$RULES" ]; then
    echo "▸ check against $RULES"
    "$UML" check --from "$ARTIFACT" --rules "$RULES" --format json --no-fail \
        --output "$OUT_DIR/check.json"
    "$UML" check --from "$ARTIFACT" --rules "$RULES" >/dev/null 2>&1 || CHECK_STATUS=$?
else
    echo "▸ check skipped (no $RULES)"
fi

# PNGs are macOS-only (the image command links UMLRender there).
if [ "$(uname)" = "Darwin" ]; then
    echo "▸ images (package + class PNG)"
    "$UML" image --from "$ARTIFACT" --package --output "$OUT_DIR/package.png" || true
    "$UML" image --from "$ARTIFACT" --output "$OUT_DIR/class.png" || true
fi

echo "✓ audit bundle written to $OUT_DIR"
exit "$CHECK_STATUS"
