#!/bin/sh
# Launcher for the UML MCP server, resolved at plugin start. The plugin lives at
# .claude/plugins/code-quality/, so its .mcp.json references this as
# ${CLAUDE_PLUGIN_ROOT}/../../../Scripts/mcp_launch.sh (three levels up to the repo root).
#
# Resolution order — the LOCAL build wins, so that while developing the MCP a `swift build` is picked
# up immediately without reinstalling, and a globally-installed copy never shadows work in progress:
#   1. A local build under .build (debug first — what `swift build` produces during development —
#      then release, then the stripped artifact from Scripts/mcp_create.sh).
#   2. `uml-mcp` on PATH (a released tarball / Homebrew / Scripts/mcp_install.sh — the end-user path).
#   3. Build from source with SwiftPM (requires a Swift 6 toolchain) and run that.
#
# The server speaks JSON-RPC over stdio, so exec keeps stdin/stdout wired straight through.

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# 1. A local build — prioritized so development iteration and the checked-out plugin win.
for candidate in \
    "$ROOT/.build/artifacts/uml-mcp" \
    "$ROOT/.build/debug/UMLMCP" \
    "$ROOT/.build/release/UMLMCP"; do
    if [ -x "$candidate" ]; then
        exec "$candidate" "$@"
    fi
done

# 2. An installed binary on PATH — the toolchain-free end-user path.
if command -v uml-mcp >/dev/null 2>&1; then
    exec uml-mcp "$@"
fi

# 3. Build from source. Stderr only — stdout is the JSON-RPC channel.
echo "uml-mcp: no local or installed binary found; building from source (needs a Swift 6 toolchain)…" >&2
swift build -c release --product UMLMCP --package-path "$ROOT" >&2
exec "$ROOT/.build/release/UMLMCP" "$@"
