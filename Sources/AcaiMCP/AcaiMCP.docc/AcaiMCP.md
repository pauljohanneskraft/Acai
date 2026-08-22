# ``AcaiMCP``

The `acai-mcp` server: Açaí's read-only analysis engine exposed as Model Context Protocol tools,
so an AI agent can query a codebase instead of grepping it.

## Overview

`acai-mcp` is one of the three entry points over [AcaiLibrary](/documentation/acailibrary/) —
alongside [AcaiCLI](/documentation/acaicli/) and [AcaiApp](/documentation/acaiapp/). It speaks
JSON-RPC over stdio and takes no arguments.

It exposes nine tools, every one marked read-only:

| Tool | Answers |
| --- | --- |
| `acai_analyze` | What is this project, and can I trust the parse? |
| `acai_metrics` | Where are the coupling hotspots and god classes? |
| `acai_quality` | Does this violate the architecture rules? |
| `acai_callgraph` | Hot methods, mutual recursion, or dead code? |
| `acai_inspect` | Where is type X / which types match this selector? |
| `acai_impact` | What breaks if I change this? |
| `acai_diff` | What changed between these two revisions? |
| `acai_diagram` | Show me the structure as DOT or Mermaid text. |
| `acai_image` | Show me the structure as a picture. *(macOS only)* |

Every result carries `file:line` jump targets, and nothing in the server calls a model — it is a
deterministic sensor, leaving interpretation to the caller.

> Note: This page documents the server's *internals* — the tool protocol, argument coercion and the
> snapshot cache. For installing and wiring it into a client, plus every tool's full input schema,
> see [`Documentation/MCP.md`](https://github.com/pauljohanneskraft/Acai/blob/main/Documentation/MCP.md)
> in the repository.

### One parse per project

``AnalysisSnapshotCache`` holds a single parsed artifact per project path and shares it across every
tool call, so a multi-tool audit parses once. Invalidation is driven by a source-tree signature
(modification time, file count and a content digest) rather than a timer, and a call can force a
re-parse with `refresh: true`. The cache is an actor, so concurrent calls on an uncached project
queue rather than duplicating work.
