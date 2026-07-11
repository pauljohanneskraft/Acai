---
name: audit
description: Use the UML tool to deterministically surface code-quality and architecture issues in a codebase (its own or any supported language) — coupling / fan-in-out, dependency cycles, responsibility bloat (god classes), layering/boundary violations, and visual structure — then drive and verify fixes. Use when asked to audit code quality, find architectural debt, prepare or de-risk a refactor, or gate architecture in CI.
---

# Code-quality audit (dogfood the UML tool)

The tool is a **deterministic sensor**: it sees what reading files one at a time cannot — global
coupling (fan-in/out), whole-graph facts (dependency cycles, layering breaches), and visual gestalt
(hairballs, lopsided layouts). You are interpretation + actuation: turn a metric into a judgment,
open the *specific* files it flags, fix, then re-run to confirm the metric moved. Measurement
narrows; reading confirms; editing fixes; re-running verifies. Nothing in the tool calls an LLM.

## Front door: the MCP tools

When the `uml` plugin's MCP server is connected, the engine is available as read-only tools — this is
the default path for the interactive audit. Call **`uml_analyze <path>` with `health: true` first**
(parse-health trust score: a low score means the rest is built on an incomplete parse), then
**`uml_analyze <path>`** to index the project once; every other tool reuses that in-process snapshot
(pass `refresh: true` after you edit). All return JSON with `file:line` jump targets.

- **`uml_analyze`** — index the project (languages, type/relationship counts). Pass `health: true` for
  the full parse-health trust report; gate the whole audit on it.
- **`uml_metrics`** — the full metric set (the single home for the raw numbers): per-module
  coupling/instability, per-type fan-in/out, weighted methods (WMC), inheritance depth, cohesion
  (LCOM), data-class score. High `fanOut` = too many collaborators (SRP risk); high `fanIn` =
  hub/change-magnet; high `weightedMethods` = god class. Rank client-side and triage the outliers.
- **`uml_quality`** — the code-quality gate and the single home for verdicts. Omit `rules` for the
  built-in curated smell budgets (long parameter lists, data classes, low cohesion, feature envy, deep
  nesting, god classes) — each finding carries a `file:line` and a fix hint. Pass a `rules:` path to
  gate a `quality.yml` (forbidden deps, layering, cycles, budgets, stereotype contracts). Set
  `explore: true` (with `scope: modules|types|all`) to also list dependency cycles and never fail.
- **`uml_inspect`** — enumerate types **and** members filtered by a type selector (`kind`, `module`,
  `minMembers`, `stereotype`, …) plus member facets (`memberKind`, `minParameters`, `publicVars`,
  `overrides`). The highest-leverage lookup: "which public classes have a 4+-parameter method?" Set
  `enums: true` for the enum-case inventory (raw + associated values).
- **`uml_callgraph`** — three cuts of the call graph via `mode`: `metrics` (per-method fan-in/out,
  recursion, hot methods, coverage; `scope: type:Name|module:Name`), `cycles` (method-level SCCs /
  mutual recursion), `deadcode` (uncalled non-entry-point candidates — always read the reported
  **coverage**, since low coverage means more false positives).
- **`uml_impact <type>`** — the blast radius (transitive dependents) of a type — "is this safe to
  change?" before you touch it.
- **`uml_diff` (`pathOld`, `pathNew`)** — the structural delta between two revisions (added/removed
  types, changed relationships, metric movement). Each side is a source dir or a `.json` baseline —
  the drift check, "what did this change alter?".
- **`uml_diagram`** (`kind: class|package|sequence|state|callgraph`, `format: dot|mermaid`) — the
  diagram source as text you can embed; **`uml_image`** (macOS) returns a PNG you can *see*. Read the
  package/class diagram for hairballs, lopsided layouts, edges pointing "up" the layer stack, orphans;
  `focus` a type to zoom its neighbourhood.

## When to drop to the CLI

The MCP now covers sensing, diagrams, images, and drift. Reach for the `uml` CLI (build first:
`swift build`, binary at `.build/debug/UMLCLI`) only for the things that are inherently process- or
file-shaped:

1. **Gate quality in CI** — `uml quality --source . --rules quality.yml` **fails the build**
   (non-zero exit); the MCP's `uml_quality` only returns a verdict. Omit `--rules` to gate on the
   built-in smell budgets. Gate module cycles as a hard invariant. Also `uml diff --format json` /
   `uml quality --baseline <name>` in a CI step to fail on adverse drift.
2. **Author rules** — `uml rules init` generates a candidate `quality.yml` seeded from the current
   worst-case metrics (no MCP tool).
3. **One-shot file audit** — `Scripts/audit.sh [SOURCE_DIR] [OUTPUT_DIR] [RULES_YAML]` analyzes once
   and fans every command out against that snapshot, writing `metrics.json`, `quality-explore.json`,
   `deadcode.json`, `callgraph.json`, `call-cycles.json`, `health.json`, `inspect.json`, `enums.json`,
   `package.dot`, `quality.json`, PNGs.
4. **Persisted baselines** — `uml store` / `uml list` keep named snapshots across sessions (the MCP's
   cache is in-process; for cross-session drift, pass `uml_diff` a stored `.json` baseline instead).

## The loop

Capture a baseline → read the *specific* files the tool flags → make a bounded fix → re-run the
audit and assert the metric moved the right way (and no new cycles / budget breaches). Cross-check
metric outliers against the diagrams before acting.

## Interpretation cautions

The tool measures; you judge — not every outlier is a defect (a data-model core legitimately has
high fan-in; per-grammar parsers are legitimately complex). Type identity flows as bare names, so
results depend on the producer's conventions; module attribution is provenance-aware
(`Relationship.origin` / `ModuleAttribution`). When a question isn't expressible, extend the engine —
add a `MetricBudget.Metric`, a `Selector` facet, or a CLI command — keeping it language-agnostic
(no `switch` over `SourceLanguage`; see `CLAUDE.md` and the `add-language` skill).
