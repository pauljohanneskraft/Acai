# ``AcaiMCP``

The `acai-mcp` server: Açaí's analysis engine as
[Model Context Protocol](https://modelcontextprotocol.io) tools, so a coding agent can query your
codebase directly instead of grepping it.

## Overview

`acai-mcp` is one of the three entry points over [AcaiLibrary](/documentation/acailibrary/) —
alongside the [AcaiCLI](/documentation/acaicli/) tool and the [AcaiApp](/documentation/acaiapp/)
SwiftUI app. This page is the complete tool and schema reference.

---

## Contents

- [Why](#Why)
- [Install](#Install)
- [Wire it up](#Wire-it-up)
- [The tools](#The-tools)
- [The snapshot cache](#The-snapshot-cache)
- [Language filtering](#Language-filtering)
- [The bundled audit skill](#The-bundled-audit-skill)
- [Differences from the CLI](#Differences-from-the-CLI)

---

## Why

An agent reading files one at a time cannot see global facts. It can't tell you which type has the highest fan-in across 900 files, whether your module graph has a cycle, or what would break if you deleted a class. Those are whole-graph questions, and answering them by reading is either impossible or ruinously expensive in context.

`acai-mcp` answers them deterministically. Nothing in it calls a model: it parses your code, computes the graph, and returns JSON with `file:line` jump targets. The agent supplies judgement; the tool supplies measurement.

Every tool is marked **read-only**. The server never writes to your source tree.

---

## Install

The server ships in the same release archives as the CLI — see [AcaiCLI](/documentation/acaicli/). Or build it:

```sh
./Scripts/mcp_create.sh     # swift build -c release --product AcaiMCP
./Scripts/mcp_install.sh    # into /usr/local/bin (or /opt/homebrew/bin)
./Scripts/mcp_uninstall.sh
```

The binary is `acai-mcp`. It takes no arguments and speaks JSON-RPC over stdio.

---

## Wire it up

### Claude Code — the bundled plugin

The repository ships a `code-quality` plugin that pairs the server with an audit skill:

```
/plugin marketplace add pauljohanneskraft/Acai
/plugin install code-quality@acai
```

The plugin launches the server through `Scripts/mcp_launch.sh`, which resolves a binary in this order:

1. A local build in the checkout — `.build/artifacts/acai-mcp`, then `.build/debug/AcaiMCP`, then `.build/release/AcaiMCP`. **Local wins first**, so a `swift build` during development is picked up immediately and an installed copy never shadows work in progress.
2. `acai-mcp` on your `PATH`.
3. Otherwise it builds from source on demand (needs a Swift 6 toolchain), logging to stderr so the stdout JSON-RPC channel stays clean.

### Any other MCP client

```json
{
  "mcpServers": {
    "acai": {
      "command": "acai-mcp",
      "args": []
    }
  }
}
```

Or point at a checkout without installing anything — this builds on first use:

```json
{
  "mcpServers": {
    "acai": {
      "command": "/absolute/path/to/Acai/Scripts/mcp_launch.sh",
      "args": []
    }
  }
}
```

On macOS the app can generate this for you: **Settings → Connect via MCP** locates an installed binary and hands you a copyable snippet.

---

## The tools

Ten tools on macOS, **eight on Linux** — `acai_image` links the SwiftUI renderer and `acai_hotspots` links libgit2; both are compiled out elsewhere.

Every tool takes `path` (required), and most also accept:

| Property | Type | Meaning |
| --- | --- | --- |
| `path` | string | Project root to analyze — absolute or relative. May also be a `.json` artifact. |
| `languages` | string[] | Language filter. Empty means all. |
| `refresh` | boolean | Re-analyze instead of reusing the cached snapshot. |
| `includeGenerated` | boolean | Include machine-generated types. Default `false`. |

> **No JSON-Schema `default` keywords.** Every documented default is applied inside the tool, not declared in the schema, so a schema-driven client won't pre-fill them. Passing a wrong-typed value throws rather than being ignored — `refresh: "true"` is rejected.

---

### `acai_analyze`

Index a codebase and return a summary: languages, type and relationship counts, parse-health score. **Call this first** when reasoning about an unfamiliar or large project — every other tool reuses the cached parse.

| Property | Type | Notes |
| --- | --- | --- |
| `path` * | string | |
| `languages` | string[] | |
| `refresh` | boolean | |
| `includeGenerated` | boolean | |
| `health` | boolean | Return the full parse-health report (trust score + diagnostics with `file:line`) instead of the summary. |

Deliberately returns a compact snapshot, not the full model — the whole artifact is far too large for a context window. Use the CLI's `acai analyze` if you want the complete JSON.

> **Run `health: true` before trusting anything else.** A low score means the parse is incomplete, and every metric, cycle and diagram built on it is unreliable.

You don't have to run it separately every time: `acai_metrics`, `acai_quality`, `acai_callgraph`,
`acai_inspect`, `acai_diff` and `acai_dependents` each embed a compact `health` object (`score`,
`diagnosticCount`, `countsByKind` — the same shape `acai_analyze`'s `health: true` report uses, without
its full per-diagnostic list) in their JSON result, so a caller reads one field regardless of which
tool produced it. `acai_diff` combines both sides into the weaker-trust view. `acai_diagram` has no
JSON result to embed a field in, so below `HealthCheck.trustThreshold` (`0.8`) it instead returns an
extra leading text block naming the diagnostic count before the diagram text.

### `acai_metrics`

Per-module coupling and instability; per-type fan-in/out, weighted methods, inheritance depth, cohesion (LCOM) and data-class score. Use it to find god classes and coupling hotspots before a refactor.

Properties: `path` *, `languages`, `refresh`, `includeGenerated`.

Rank client-side: high `fanOut` means too many collaborators (an SRP risk), high `fanIn` means a change-magnet hub, high `weightedMethods` means a god class.

Result shape: `{ "metrics": <CodeMetrics>, "health": <HealthCheck.Summary> }`.

### `acai_quality`

Check against a declarative rules file: forbidden dependencies, cycles, layering, metric budgets, stereotype contracts, and the curated smells. Each violation carries `file:line` and a fix hint.

| Property | Type | Notes |
| --- | --- | --- |
| `path` * | string | |
| `languages` | string[] | |
| `refresh` | boolean | |
| `rules` | string | Path to the YAML rules file. Omit for the built-in smell budgets. |
| `explore` | boolean | Rank findings and additionally list dependency cycles, with no pass/fail gate. |
| `scope` | `modules` \| `types` \| `all` | Cycle scope in explore mode. Default `all`. |
| `baseline` | string | Snapshot to compare against: a `.json` artifact or a source directory, resolved exactly like `acai_diff`'s `pathOld`. A directory is analyzed as it is *now*, so it must be a different checkout (an old worktree, say); for the same tree, pass a `.json` written before the edit. `baseline` equal to `path` is rejected with `invalidParams`. |

Cycle findings are appended only when `explore` is set *and* the rules file doesn't already own the cycle check. The rules-file schema is documented under [AcaiCLI](/documentation/acaicli/).

> **This tool cannot gate CI.** It returns a verdict but never a non-zero exit status. Use `acai quality` on the CLI for that.

Note it has no `includeGenerated` — generated-type filtering goes through the rules' own `includeGeneratedTypes` key instead.

#### Proving a movement with `baseline`

A rules file's `movements` section states how a metric was expected to move — `{ target: { typeGlob: "Foo" }, metric: fanOut, minImprovement: 2 }` means *`Foo`'s `fanOut` must have decreased by at least 2*. Omitting `minImprovement` means "must not get worse". Declaring a movement also guards its target against a hidden regression: every other metric of the same scope on that target must not have worsened either, so an improvement bought by a cost elsewhere doesn't pass.

Movements are evaluated **only** when `baseline` is given. A rules file that declares one without a `baseline` is rejected with `invalidParams` rather than passing on a check that never ran — the same refusal `acai quality` makes for `--baseline`.

A movement in the wrong direction lands in `quality.violations` as an ordinary violation with `ruleKind: "movement"`, whose `detail` carries `metric`, `before` and `after` — so `structuredContent` alone is enough to branch on, with no text parsing:

```json
{ "ruleKind": "movement", "subject": "Foo", "message": "Foo: fanOut regressed from 3 to 5.",
  "detail": { "metric": "fanOut", "before": "3", "after": "5" } }
```

This closes the audit loop — snapshot with `acai analyze --source <dir> --include-generated --output <file>.json` (outside the analyzed tree), fix, re-run with that `.json` as `baseline`, and read the verdict. The project directory itself can't serve as the previous snapshot: a directory baseline is analyzed as it is now, so it has to be a `.json` written before the edit or a different checkout.

Result shape: `{ "quality": <QualityReport>, "drift": <ArtifactDiff>?, "health": <HealthCheck.Summary> }`.
`drift` is the same structural delta `acai_diff` returns, present only when `baseline` was given — so the
key's absence tells a caller this was a plain gate run. `QualityReport` carries its own top-level
`schemaVersion`, starting at `1`.

### `acai_callgraph`

Three cuts of the static call graph.

| Property | Type | Notes |
| --- | --- | --- |
| `path` * | string | |
| `languages`, `refresh`, `includeGenerated` | | |
| `mode` | `metrics` \| `cycles` \| `deadcode` | Default `metrics`. |
| `scope` | string | `type:Name` or `module:Name`. Ignored in `deadcode` mode. |

- **`metrics`** — per-method fan-in/out, recursion, resolution coverage. Finds hot methods.
- **`cycles`** — method-level mutual recursion and tangled clusters.
- **`deadcode`** — uncalled methods not reachable by contract (public API, overrides, protocol requirements, entry points). **Always read the reported coverage** — it's the false-positive floor.

Result shape wraps each mode's data alongside `health`: `{ "callGraph": <CallGraphMetrics.Report>, "health": ... }`, `{ "cycles": [<MethodCycles.Cluster>], "health": ... }`, or `{ "deadCode": <DeadCodeScan.Report>, "health": ... }`.

### `acai_inspect`

Enumerate types and members matching a selector, each with a `file:line` jump target. The highest-leverage lookup here: *"which public classes in module Y have a method with four or more parameters?"* — answered without grepping.

| Property | Type |
| --- | --- |
| `path` *, `languages`, `refresh`, `includeGenerated` | |
| `module`, `type` | string — glob (`*`, `?`) |
| `kind` | `class` \| `actor` \| `struct` \| `enum` \| `protocol` \| `interface` \| `trait` \| `typeAlias` \| `object` \| `extension` \| `annotation` \| `module` \| `record` \| `mixin` |
| `minAccess` | `public` \| `open` \| `internal` \| `protected` \| `private` \| `filePrivate` \| `packagePrivate` |
| `stereotype`, `annotation` | string |
| `minMembers`, `minNesting` | integer |
| `memberKind` | `property` \| `method` \| `initializer` \| `deinitializer` \| `subscript` |
| `minParameters` | integer |
| `publicVars`, `overrides` | boolean |
| `enums` | boolean — inventory enum cases with raw and associated values instead |

Legal values for `kind`, `minAccess` and `memberKind` are the same lists the CLI enumerates (see [AcaiCLI](/documentation/acaicli/)), and each argument's `enum` in the schema is that list. An unrecognised value is an `invalidParams` error naming the argument, the value received and the accepted values — the filter is never dropped, which would silently widen the call to every type. `publicVars: false` still means "no constraint", not "exclude".

Result shape: `{ "types": [<TypeQuery.TypeRow>], "health": <HealthCheck.Summary> }`, or with `enums: true`: `{ "enums": [<EnumInventory.Entry>], "health": <HealthCheck.Summary> }`.

### `acai_dependents`

The blast radius of a type: every type that transitively depends on it, with `file:line`. Use it before refactoring or deleting something.

| Property | Type | Notes |
| --- | --- | --- |
| `path` * | string | |
| `type` * | string | Simple name, qualified name, or id. |
| `languages`, `refresh`, `includeGenerated` | | |
| `depth` | integer | Limit reverse reachability to *n* hops. |

The only tool with two required properties.

Result shape: `{ "impact": <ImpactAnalysis.Report>, "health": <HealthCheck.Summary> }` — the key keeps its original name, so the result shape is unchanged by the rename.

> **`acai_impact` still answers.** It is a deprecated alias for `acai_dependents`, identical in schema and result. It is left out of `tools/list`, so an agent only ever discovers the current name, and it will be removed in a later major release.

### `acai_diff`

Structural delta between two revisions — added/removed types, changed relationships, metric movement.

| Property | Type | Notes |
| --- | --- | --- |
| `pathOld` * | string | Source directory or `.json` baseline. |
| `pathNew` * | string | Same. |
| `languages` | string[] | Applies to both sides. |
| `refresh` | boolean | Applies to both sides. |
| `includeGenerated` | boolean | Applies to both sides before diffing, so a generated type is never reported as added or removed by the filtering itself. Default `false`. |

Note there's no `path` here. **Both sides must be real filesystem paths** — unlike the CLI, a bare stored-analysis name is not resolved. Produce baselines with `acai store` on the CLI and pass the resulting `.json` path. A baseline whose `schemaVersion` is newer than this build understands is rejected with the found and expected version numbers, rather than being misread.

Result shape: `{ "diff": <ArtifactDiff>, "health": <HealthCheck.Summary> }` — `health` combines both sides into the weaker-trust view (the lower score, diagnostic counts summed).

### `acai_diagram`

Render a diagram as DOT or Mermaid text you can embed in a reply.

| Property | Type | Notes |
| --- | --- | --- |
| `path` * | string | |
| `languages`, `refresh` | | |
| `kind` | `class` \| `package` \| `moduleCoupling` \| `sequence` \| `state` \| `callgraph` | Default `class`. |
| `format` | `dot` \| `mermaid` | **Default `mermaid`** — note the CLI defaults to `dot`. |
| `focus`, `focusDepth` | string, integer | Class diagram only. |
| `scope` | string | Call graph: `type:Name` or `module:Name`. |
| `sequenceFrom` | string | Required for `kind: sequence`. |
| `stateFrom` | string | Required for `kind: state`. |
| `maxDepth`, `maxStates` | integer | Defaults 5 and 20. |
| `maxNodes` | integer | Class, package and `moduleCoupling` only. Fails beyond this many nodes, naming the count (default `2000`). |
| `map` | string[] | `Protocol=Concrete` receiver mappings for sequence tracing. |

`kind: moduleCoupling` renders the same module graph as `kind: package`, but labels each node with its full
Martin metric set (`Ca`/`Ce`/`I`/`A`/`D`) and names its main-sequence zone — `balanced`, `zone of pain` or
`zone of uselessness` — in the label text rather than by fill colour alone. Edges that breach the
Stable-Dependencies Principle (a dependency on a *less* stable module) are dashed in DOT, dotted in Mermaid,
and labelled `(SDP)`. Use it to audit layering; use `kind: package` for the plain dependency shape.

`sequenceFrom` and `stateFrom` are required in practice for their kinds, but the schema doesn't express that. Setting `focus` forces `groupBy` off and traverses in both directions — a focused view is a local neighbourhood, and grouping would split it into mismatched clusters.

Returns raw text with no structured content, except a leading text block warning of low parse health
(see [The tools](#The-tools)) when the score is below `HealthCheck.trustThreshold`.

### `acai_hotspots` — macOS only

Rank files by churn × complexity: how often a file changes, against how complex its types are. Use it to decide where a refactoring budget pays off most, or which files a risky change is likeliest to touch.

Churn is a git-history walk, so `path` must be inside a git checkout — a plain folder is `invalidParams` naming the missing history, never an empty list. A shallow clone is refused rather than counted.

| Property | Type | Notes |
| --- | --- | --- |
| `commits` | integer | How many commits of history to walk. Default `50`. |
| `top` | integer | Limit the ranked list. |

Plus `path` *, `languages`, `refresh`, `includeGenerated`.

Result shape: `{ "churnThreshold": <median>, "complexityThreshold": <median>, "commitWindow": <n>, "filesScored": <n>, "hotspotCount": <n>, "hotspots": [{ "path", "type", "churn", "complexity", "score", "isHotspot" }] }`, ranked highest score first. `type` is the declared type whose most complex method sets `complexity`, omitted for a file that declares none. `hotspotCount` counts every file above both medians, even when `top` returns fewer.

### `acai_image` — macOS only

The same diagram families rendered to a PNG the agent can actually see. Use it when a visual beats text: hairballs, layout, hot nodes.

Identical to `acai_diagram`, minus `format`, plus:

| Property | Type | Notes |
| --- | --- | --- |
| `kind` | `class` \| `package` \| `sequence` \| `state` \| `callgraph` | Default `class`. No `moduleCoupling` — it has no image renderer, as `acai image` also rejects `--module-coupling`. Render it as text with `acai_diagram`. |
| `scale` | number | Resolution factor, default `2`. |
| `theme` | `light` \| `dark` | Default light. `default` is still parsed as a deprecated spelling of `light`, but the schema no longer advertises it. |

Returns base64 PNG image content.

---

## The snapshot cache

One parse per project path, shared by every tool in the process. This is what makes a multi-tool audit affordable.

- **Keyed on the resolved path only.** Symlinks resolved, path standardised.
- **Invalidated by a source-tree signature** — latest modification time, file count, and a content digest — not by a timer. Renames, moves and content swaps that preserve mtime are all caught. Build and dependency directories (`.build`, `.git`, `node_modules`, `DerivedData`, `Pods`, `__pycache__`, `.venv`, …) are skipped.
- **`refresh: true`** forces a re-parse. Rarely needed, since the signature detects edits on its own.
- **Lifetime is the process.** No eviction, no expiry. Cross-session baselines have to go through `acai store` on the CLI.
- **Concurrent calls serialise safely.** Two simultaneous calls on an uncached project queue rather than parsing twice.
- `path` may be a `.json` artifact instead of a directory — that's how `acai_diff` consumes baselines.

> ⚠️ **`languages` is not part of the cache key.** Calling `acai_analyze(path: X, languages: ["swift"])` and then `acai_metrics(path: X, languages: ["kotlin"])` silently returns the **Swift-filtered** artifact — the language filter only takes effect on a cache miss. If you need to switch language filters on the same path, pass `refresh: true`. (`includeGenerated` is applied after the cache and is safe to vary freely.)

---

## Language filtering

`languages` accepts, case-insensitively: `swift`, `kotlin`, `java`, `typescript`, `javascript`, `dart`, `python`, `c`, `cpp`. The schema advertises that list as the array's `items.enum`.

- **An unknown name is an `invalidParams` error** naming `languages`, the value received and the accepted names, raised before anything is parsed — as the CLI's `--language` rejects it. A typo never falls back to analysing every language.
- **A value that isn't an array of strings** is rejected the same way.
- **An empty array** (or omitting the argument) means *no restriction*.

---

## The bundled audit skill

The `code-quality` plugin ships an `audit` skill encoding a methodology for using these tools well. Its framing: the tool is a **deterministic sensor**, you are interpretation and actuation.

The loop is *measurement narrows → reading confirms → editing fixes → re-running verifies*:

1. Gate on `acai_analyze` with `health: true`. A bad parse invalidates everything downstream.
2. `acai_analyze` once to index; every other call reuses that snapshot.
3. `acai_metrics` to rank outliers, `acai_quality` for verdicts.
4. `acai_inspect` / `acai_callgraph` / `acai_dependents` to localise — and the diagram tools to cross-check the numbers against visual gestalt.
5. Open the *specific* flagged files, make a bounded fix, re-run, and assert the metric actually moved and no new cycle appeared — `acai_quality` with `baseline` set to a pre-fix `.json` snapshot makes that assertion for you.

The skill is explicit that the tool measures and you judge: a data-model core legitimately has high fan-in, and a metric is a question, not a defect.

Four jobs are inherently process-shaped and belong on the CLI: **CI gating** (only the CLI exits non-zero), **`acai rules`** (no MCP equivalent), **`Scripts/audit.sh`** report bundles, and **`acai store` / `acai list`** for cross-session baselines.

---

## Differences from the CLI

The tools mirror CLI commands closely, but not exactly. Where they diverge:

| Tool | Divergence |
| --- | --- |
| `acai_analyze` | Returns a compact summary, not the full model. `health: true` does mirror `acai analyze --health`. |
| `acai_quality` | Never exits non-zero — it can't gate CI. `baseline: <dir>` analyzes that directory's *current* contents, so it must be a different checkout or a `.json` written before the edit; `--baseline <dir>` instead reads that directory's *stored* analysis, and also accepts a stored analysis name. |
| `acai_metrics` | No `--sort` / `--top`; rank client-side. JSON only. |
| `acai_callgraph` | No `--top`, no `--no-fail`. JSON only. |
| `acai_diff` | Both sides must be filesystem paths. No delta-diagram rendering. |
| `acai_diagram` | Defaults to `mermaid` where the CLI defaults to `dot`. Exposes none of the class-diagram flags, no theme, no config file, no focus direction/relationship control. |
| `acai_image` | No `--grouping`, `--hide-members`, `--min-access`, or delta-image inputs. |
| `acai_hotspots` | JSON only — no human table. |

`acai_inspect` and `acai_dependents` are at full parity.

**No MCP equivalent at all:** `store`, `list`, `rules`.
