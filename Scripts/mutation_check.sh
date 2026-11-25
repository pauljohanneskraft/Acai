#!/bin/bash
# Reverts each hunk <base>...HEAD touches under the analysis engine and its language plugins, one at
# a time, and reports every hunk whose tests still pass as *surviving* — a change no test can see.
# A hunk that no longer compiles once reverted is reported as *not applicable*, never as caught.
# It reports and never fails: a pure refactor legitimately survives.
#
#   Scripts/mutation_check.sh origin/main
#
# `--paths` instead of a base prints the paths it covers, one per line, so a caller deciding whether
# to run it filters on the same list.
#
# MUTATION_CHECK_TIME_LIMIT bounds the whole run (default 1200 seconds); hunks it does not reach are
# named in the report. With GITHUB_STEP_SUMMARY set, the report is appended there too.
set -euo pipefail

# The engine and its language plugins. A silent test gap anywhere else is another check's business.
MODULES="AcaiCore AcaiDiagram AcaiTreeSitter AcaiSwift AcaiJS AcaiJVM"
MODULES="$MODULES AcaiDart AcaiPython AcaiCFamily CPythonScanner"
TIME_LIMIT="${MUTATION_CHECK_TIME_LIMIT:-1200}"
STARTED=$(date +%s)

# coreutils' `timeout`, which macOS does not ship. Without it the budget is only checked between
# hunks, so a single build or test run can overrun it.
TIMEOUT=$(command -v timeout || command -v gtimeout || true)

bounded() {
    if [ -n "$TIMEOUT" ]; then
        "$TIMEOUT" "$@"
    else
        "${@:2}"
    fi
}

if [ "${1:-}" = "--paths" ]; then
    tr ' ' '\n' <<< "$MODULES" | sed 's|^|Sources/|'
    exit 0
fi
if [ $# -ne 1 ]; then
    echo "usage: Scripts/mutation_check.sh <base> | --paths" >&2
    exit 2
fi

cd "$(git rev-parse --show-toplevel)"
if ! BASE=$(git rev-parse --verify --quiet "$1^{commit}"); then
    echo "✗ Not a commit: $1" >&2
    exit 2
fi

PATHSPEC=()
for MODULE in $MODULES; do
    PATHSPEC+=("Sources/$MODULE")
done

WORK=$(mktemp -d)
TREE="$WORK/tree"
SCRATCH="$WORK/build"
trap 'git worktree remove --force "$TREE" >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Its own worktree and its own scratch path: this never touches the checkout it runs from.
git worktree add --detach --quiet "$TREE" HEAD

mkdir "$WORK/hunks"
git diff --unified=0 --no-color --no-ext-diff --no-renames "$BASE...HEAD" -- "${PATHSPEC[@]}" |
    awk -v dir="$WORK/hunks" -v catalog="$WORK/hunks.tsv" '
        /^diff --git / { header = $0 "\n"; inhunk = 0; out = ""; next }
        !inhunk && /^(old|new|deleted file|new file|copy|rename|similarity|dissimilarity|index) / {
            header = header $0 "\n"; next
        }
        !inhunk && /^--- / {
            header = header $0 "\n"
            removed = ($0 == "--- /dev/null") ? "" : substr($0, 7)
            next
        }
        !inhunk && /^\+\+\+ / {
            header = header $0 "\n"
            path = ($0 == "+++ /dev/null") ? removed : substr($0, 7)
            next
        }
        /^@@/ {
            inhunk = 1
            out = sprintf("%s/%04d.patch", dir, ++n)
            printf "%s%s\n", header, $0 > out
            # The new-side range is what a reviewer sees in the file as it stands.
            range = $0
            sub(/^.*\+/, "", range)
            sub(/ .*$/, "", range)
            start = range
            count = 1
            if (split(range, parts, ",") == 2) { start = parts[1]; count = parts[2] }
            location = start
            if (count == 0) location = start " (deletion)"
            else if (count > 1) location = start "-" (start + count - 1)
            printf "%s\t%s\t%s\n", out, path, location >> catalog
            next
        }
        inhunk && out { print >> out }
    '

if [ ! -s "$WORK/hunks.tsv" ]; then
    echo "✓ No hunks under the engine or its plugins between $1 and HEAD."
    exit 0
fi

# Which suites cover a module: every test target that reaches it through the package graph, so a
# newly registered language needs no entry here.
DUMP="$WORK/package.json"
swift package --package-path "$TREE" --scratch-path "$SCRATCH" dump-package > "$DUMP"

echo "▸ Building HEAD to compare against"
if ! swift build --package-path "$TREE" --scratch-path "$SCRATCH" --build-tests > "$WORK/baseline.log" 2>&1; then
    echo "✗ HEAD does not build, so a reverted hunk proves nothing:" >&2
    tail -30 "$WORK/baseline.log" >&2
    exit 1
fi

SURVIVING=()
SKIPPED=()
UNREACHED=()
CAUGHT=0

# On its own descriptor: a build or test run that read stdin would otherwise eat the hunks.
while IFS=$'\t' read -r PATCH FILE LOCATION <&3; do
    REMAINING=$((TIME_LIMIT - ($(date +%s) - STARTED)))
    if [ "$REMAINING" -le 0 ]; then
        UNREACHED+=("$FILE:$LOCATION")
        continue
    fi

    MODULE=$(cut -d/ -f2 <<< "$FILE")
    SUITES=$(jq -r --arg module "$MODULE" '
        ([.targets[] | {key: .name, value: [.dependencies[] | (.byName // .target) | select(. != null) | .[0]]}]
            | from_entries) as $deps
        | def closure($name): [$name] + ((($deps[$name] // []) | map(closure(.)) | add) // []);
          [.targets[] | select(.type == "test") | .name | select(closure(.) | index($module))] | .[]
    ' "$DUMP")
    if [ -z "$SUITES" ]; then
        SKIPPED+=("$FILE:$LOCATION — no test target reaches $MODULE")
        continue
    fi

    echo "▸ $FILE:$LOCATION reverted — $(tr '\n' ' ' <<< "$SUITES")"
    if ! git -C "$TREE" apply --reverse --unidiff-zero "$PATCH" 2>/dev/null; then
        SKIPPED+=("$FILE:$LOCATION — does not reverse-apply on its own")
        continue
    fi

    FILTERS=()
    for SUITE in $SUITES; do
        FILTERS+=(--filter "$SUITE")
    done
    STATUS=0
    bounded "$REMAINING" swift build --package-path "$TREE" --scratch-path "$SCRATCH" --build-tests \
        > "$WORK/build.log" 2>&1 || STATUS=$?
    REMAINING=$((TIME_LIMIT - ($(date +%s) - STARTED)))
    if [ "$STATUS" -eq 124 ] || [ "$REMAINING" -le 0 ]; then
        UNREACHED+=("$FILE:$LOCATION")
        echo "  — out of time"
    elif [ "$STATUS" -ge 128 ]; then
        SKIPPED+=("$FILE:$LOCATION — the build was killed by signal $((STATUS - 128))")
        echo "  — inconclusive"
    elif [ "$STATUS" -ne 0 ]; then
        SKIPPED+=("$FILE:$LOCATION — does not compile on its own")
        echo "  — not applicable"
    else
        STATUS=0
        bounded "$REMAINING" swift test --package-path "$TREE" --scratch-path "$SCRATCH" --parallel \
            --skip-build "${FILTERS[@]}" > "$WORK/test.log" 2>&1 || STATUS=$?
        if [ "$STATUS" -eq 124 ]; then
            UNREACHED+=("$FILE:$LOCATION")
            echo "  — out of time"
        elif [ "$STATUS" -ge 128 ]; then
            # A run the kernel killed says nothing either way, and reading it as caught would hide a
            # survivor.
            SKIPPED+=("$FILE:$LOCATION — the test run was killed by signal $((STATUS - 128))")
            echo "  — inconclusive"
        elif [ "$STATUS" -eq 0 ]; then
            SURVIVING+=("$FILE:$LOCATION")
            echo "  ✗ surviving — every suite still passed"
        else
            CAUGHT=$((CAUGHT + 1))
            echo "  ✓ caught"
        fi
    fi
    git -C "$TREE" reset --hard --quiet HEAD
    git -C "$TREE" clean -qfd
done 3< "$WORK/hunks.tsv"

{
    echo
    echo "## Mutation check"
    echo
    printf '%s hunk(s) against `%s`: %s caught, %s surviving, %s not applicable, %s not reached.\n' \
        "$(wc -l < "$WORK/hunks.tsv")" "$1" "$CAUGHT" "${#SURVIVING[@]}" "${#SKIPPED[@]}" "${#UNREACHED[@]}"
    if [ "${#SURVIVING[@]}" -gt 0 ]; then
        printf '\n### Surviving — no test sees this change\n\n'
        printf -- '- `%s`\n' "${SURVIVING[@]}"
    fi
    if [ "${#SKIPPED[@]}" -gt 0 ]; then
        printf '\n### Not applicable\n\n'
        printf -- '- %s\n' "${SKIPPED[@]}"
    fi
    if [ "${#UNREACHED[@]}" -gt 0 ]; then
        printf '\n### Not reached within %ss\n\n' "$TIME_LIMIT"
        printf -- '- `%s`\n' "${UNREACHED[@]}"
    fi
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
