#!/usr/bin/env bash
# Generates Sources/AcaiApp/Resources/Licenses.json from Package.resolved and the dependency
# checkouts under .build/checkouts/.
#
# Usage: Scripts/generate_licenses.sh
#   Requires the dependencies to already be checked out (`swift package resolve` or `swift build`).
set -euo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly RESOLVED_PATH="$REPO_ROOT/Package.resolved"
readonly CHECKOUTS_DIR="$REPO_ROOT/.build/checkouts"
readonly OUTPUT_PATH="$REPO_ROOT/Sources/AcaiApp/Resources/Licenses.json"
readonly SCHEMA_VERSION=1
readonly LIBGIT2_UPSTREAM="https://github.com/libgit2/libgit2"

command -v jq >/dev/null 2>&1 || { echo "error: jq is required (brew install jq)." >&2; exit 1; }

if [[ ! -f "$RESOLVED_PATH" ]]; then
    echo "error: $RESOLVED_PATH not found." >&2
    exit 1
fi
if [[ ! -d "$CHECKOUTS_DIR" ]]; then
    echo "error: $CHECKOUTS_DIR not found. Run 'swift package resolve' (or 'swift build') first so" \
        "every dependency's source — including its LICENSE/COPYING file — is actually on disk." >&2
    exit 1
fi

# Line breaks are collapsed to spaces before matching — several license bodies hard-wrap the
# phrases being matched at 80 columns.
classify_license() {
    local file="$1"
    local text
    text="$(tr '\n' ' ' < "$file" | tr -s ' ')"
    if [[ "$text" == *"Apache License"* && "$text" == *"Version 2.0"* ]]; then
        echo "Apache-2.0"
    elif [[ "$text" == *"GNU GENERAL PUBLIC LICENSE"* && "$text" == *"Version 2, June 1991"* ]]; then
        echo "GPL-2.0-only"
    elif [[ "$text" == *"BSD 3-Clause License"* || "$text" == *"nor the names of its contributors"* ]]; then
        echo "BSD-3-Clause"
    elif [[ "$text" == *"Permission is hereby granted, free of charge"* \
        && "$text" == *"merge, publish, distribute, sublicense"* ]]; then
        echo "MIT"
    else
        echo ""
    fi
}

mkdir -p "$(dirname "$OUTPUT_PATH")"
readonly ENTRIES_DIR="$(mktemp -d)"
trap 'rm -rf "$ENTRIES_DIR"' EXIT

echo "▸ Reading pins from $RESOLVED_PATH ..."

index=0
while IFS=$'\t' read -r identity location revision version branch; do
    checkout_name="$(basename "$location" .git)"
    checkout_path="$CHECKOUTS_DIR/$checkout_name"
    if [[ ! -d "$checkout_path" ]]; then
        echo "error: no checkout found for dependency '$identity' at $checkout_path (from $location)." \
            "Run 'swift package resolve' first." >&2
        exit 1
    fi

    license_file="$(find "$checkout_path" -maxdepth 1 -type f \( -iname "LICENSE*" -o -iname "COPYING*" \) | head -n1)"
    if [[ -z "$license_file" ]]; then
        echo "error: dependency '$identity' ($checkout_path) has no LICENSE*/COPYING* file at its root." \
            "Locate its license manually and extend this script before regenerating Licenses.json." >&2
        exit 1
    fi

    license_id="$(classify_license "$license_file")"
    if [[ -z "$license_id" ]]; then
        echo "error: could not classify the license for dependency '$identity' (file: $license_file)." \
            "Recognized fingerprints: MIT, Apache-2.0, BSD-3-Clause, GPL-2.0-only." \
            "Add a fingerprint to classify_license() in this script before regenerating Licenses.json." >&2
        exit 1
    fi

    notes=""
    if [[ "$identity" == "libgit2" ]]; then
        notes="Pinned via a fork used for AcaiApp's git engine (AcaiGit — real clone/fetch/checkout/diff"
        notes+=" plus worktree support), not the upstream project directly. Fork: $location, pinned at"
        notes+=" revision $revision"
        if [[ -n "$version" ]]; then
            notes+=" (v$version)"
        fi
        notes+=". Upstream project: $LIBGIT2_UPSTREAM. Distributed under GPL-2.0-only plus the linking"
        notes+=" exception stated at the top of its COPYING file (reproduced in full below), which is"
        notes+=" what makes linking this library from a non-GPL app permissible."
    elif [[ "$identity" == "swift-sdk" ]]; then
        notes="This project's LICENSE records an in-progress relicensing from MIT to Apache-2.0:"
        notes+=" contributions with relicensing consent are Apache-2.0, and any contribution whose"
        notes+=" author hasn't yet consented remains MIT. The full text below (as shipped in LICENSE)"
        notes+=" is presented as Apache-2.0 because that's the license the file's own governing"
        notes+=" terms are written in, but see https://github.com/modelcontextprotocol/swift-sdk/blob/main/LICENSE"
        notes+=" for the per-contribution nuance before treating this as a blanket Apache-2.0 grant."
    fi

    ref="$version"
    [[ -z "$ref" ]] && ref="$branch"

    jq -n \
        --arg name "$identity" \
        --arg version "$ref" \
        --arg revision "$revision" \
        --arg location "$location" \
        --arg licenseIdentifier "$license_id" \
        --rawfile licenseText "$license_file" \
        --arg notes "$notes" \
        '{
            name: $name,
            version: (if $version == "" then null else $version end),
            revision: $revision,
            location: $location,
            licenseIdentifier: $licenseIdentifier,
            licenseText: $licenseText,
            notes: (if $notes == "" then null else $notes end)
        }' > "$ENTRIES_DIR/$(printf '%04d' "$index").json"

    echo "  ✓ $identity → $license_id"
    index=$((index + 1))
done < <(jq -r '.pins[] | [.identity, .location, .state.revision, (.state.version // ""), (.state.branch // "")] | @tsv' "$RESOLVED_PATH")

jq -s \
    --argjson schemaVersion "$SCHEMA_VERSION" \
    --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{schemaVersion: $schemaVersion, generatedAt: $generatedAt, dependencies: .}' \
    "$ENTRIES_DIR"/*.json > "$OUTPUT_PATH"

echo "✅ Wrote $(jq '.dependencies | length' "$OUTPUT_PATH") dependency license entries to $OUTPUT_PATH"
