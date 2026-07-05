#!/bin/sh
# Launcher for the UML MCP server, resolved at plugin start. Referenced by .mcp.json as
# ${CLAUDE_PLUGIN_ROOT}/Scripts/mcp_launch.sh.
#
# Resolution order (the "both" distribution strategy from issue #106):
#   1. `uml-mcp` already on PATH (installed via Scripts/mcp_install.sh, Homebrew, or a release tarball).
#   2. A local release build under .build (from Scripts/mcp_create.sh or a prior `swift build`).
#   3. Build from source with SwiftPM (requires a Swift 6 toolchain) and run that.
#
# The server speaks JSON-RPC over stdio, so exec keeps stdin/stdout wired straight through.

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# 1. A binary on PATH — the toolchain-free path (release tarball / brew / mcp_install.sh).
if command -v uml-mcp >/dev/null 2>&1; then
    exec uml-mcp "$@"
fi

# 2. A local release build.
for candidate in "$ROOT/.build/artifacts/uml-mcp" "$ROOT/.build/release/UMLMCP"; do
    if [ -x "$candidate" ]; then
        exec "$candidate" "$@"
    fi
done

# 3. Build from source. Stderr only — stdout is the JSON-RPC channel.
echo "uml-mcp: no prebuilt binary found; building from source (needs a Swift 6 toolchain)…" >&2
swift build -c release --product UMLMCP --package-path "$ROOT" >&2
exec "$ROOT/.build/release/UMLMCP" "$@"
