#!/bin/bash
#
# Run SwiftLint's analyzer rules (unused_import, unused_declaration) over the package.
#
#   Scripts/analyze.sh                    every target under Sources/
#   Scripts/analyze.sh AcaiCore           one target
#   Scripts/analyze.sh AcaiCore AcaiJS    several
#
# Analyzer rules need a compiler log, which `swiftlint lint` does not produce. Run from any
# directory — it operates on the repository root regardless.
#
# Why per target rather than one pass over the package: analyze reads every compile job in the log
# it is handed, and the path argument only filters which violations get *reported*. Against a
# whole-package log (~2400 files, dependencies included) it runs for over half an hour; against one
# target's log (~130 files) it takes about 17 seconds.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

# Kept under .build/ so .gitignore already covers it, and reused between runs so dependencies are
# built once. Freshness comes from touching each target's own sources instead (see below), which is
# what keeps a whole-package sweep to minutes rather than rebuilding the world per target.
readonly SCRATCH=".build/analyze"
readonly LOGS="$SCRATCH/logs"

command -v swiftlint >/dev/null || { echo "swiftlint is not installed" >&2; exit 1; }

if [ $# -gt 0 ]; then
  targets=("$@")
else
  # Ask SwiftPM which Swift targets exist *on this platform* rather than listing Sources/*.
  # AcaiApp, AcaiRender, AcaiGit and AcaiPNGComparison are macOS-only (see Package.swift), so on
  # Linux their directories are present but the targets are not — `swift build --target AcaiApp`
  # fails there, which would fail this script and CI with it. This also drops C targets such as
  # CPythonScanner, which have no Swift to analyze.
  # A read loop rather than `mapfile`, which macOS's bash 3.2 does not have.
  targets=()
  while IFS= read -r t; do
    [ -n "$t" ] && targets+=("$t")
  done < <(
    swift package describe --type json 2>/dev/null \
      | tr -d ' \n' \
      | grep -oE '"module_type":"SwiftTarget","name":"[^"]+","path":"Sources/[^"]+"' \
      | grep -oE '"path":"Sources/[^"]+"' \
      | sed 's|"path":"Sources/||; s|"||' \
      | sort -u
  )
  if [ ${#targets[@]} -eq 0 ]; then
    echo "could not read the target list from swift package describe" >&2
    exit 1
  fi
fi

mkdir -p "$LOGS"

failed=()
clean=()

for target in "${targets[@]}"; do
  dir="Sources/$target"
  if [ ! -d "$dir" ]; then
    echo "no such target: $target" >&2
    failed+=("$target (no such target)")
    continue
  fi

  printf '\n==> %s\n' "$target"
  log="$LOGS/$target.log"

  # Force this module to recompile so its compile jobs appear in the log. Analyze reads the log,
  # so a module SwiftPM considers up to date contributes nothing and would be reported clean
  # without being looked at — which is what happens to every target after the first in a sweep,
  # since building one target builds its dependencies too. Touching only this target's sources
  # leaves the dependency build cached.
  find "$dir" -name '*.swift' -exec touch {} +

  # pipefail is set, so a failed build is not hidden behind tee's exit status.
  if ! swift build -v --target "$target" --scratch-path "$SCRATCH/build" | tee "$log" > /dev/null; then
    echo "    build FAILED — see $log" >&2
    failed+=("$target (build)")
    continue
  fi

  # Prove the build actually compiled something before trusting a clean analyze.
  jobs=$(grep -c 'primary-file' "$log")
  if [ "$jobs" -eq 0 ]; then
    echo "    no compile jobs in log — analyze would pass without checking. Skipped." >&2
    failed+=("$target (empty log)")
    continue
  fi

  if swiftlint analyze --strict --compiler-log-path "$log" "$dir"; then
    echo "    clean ($jobs compile jobs)"
    clean+=("$target")
  else
    failed+=("$target (violations)")
  fi
done

printf '\n---\n%d clean' "${#clean[@]}"
if [ ${#failed[@]} -gt 0 ]; then
  printf ', %d with problems:\n' "${#failed[@]}"
  printf '  %s\n' "${failed[@]}"
  exit 1
fi
printf '\n'
