---
name: code-quality-audit
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
the default path for the interactive audit. Call **`uml_doctor` first** (parse-health trust score: a
low score means the rest is built on an incomplete parse), then **`uml_analyze <path>`** to index the
project once; every other tool reuses that in-process snapshot (pass `refresh: true` after you edit).
All return JSON with `file:line` jump targets.

- **`uml_doctor`** — parse-health trust score. Gate the whole audit on it.
- **`uml_metrics`** — the full metric set: per-module coupling/instability, per-type fan-in/out,
  weighted methods (WMC), inheritance depth, cohesion (LCOM), data-class score. High `fanOut` = too
  many collaborators (SRP risk); high `fanIn` = hub/change-magnet; high `weightedMethods` = god class.
  You get every type — rank client-side and triage the outliers: split / extract / justify.
- **`uml_cycles`** (`scope: modules|types|all`) — dependency SCCs. Any multi-node cycle is a red flag;
  break it with dependency inversion / an extracted type.
- **`uml_smells`** — long parameter lists, data classes, low cohesion, feature envy, deep nesting,
  ranked most-severe first, each with a fix hint. Narrow with the selector facets.
- **`uml_inspect`** — enumerate types **and** members filtered by a type selector (`kind`, `module`,
  `minMembers`, `stereotype`, …) plus member facets (`memberKind`, `minParameters`, `publicVars`,
  `overrides`). The highest-leverage lookup: "which public classes have a 4+-parameter method?"
- **`uml_deadcode`** — methods with no resolved callers that aren't entry points. *Candidates*, not
  verdicts: always read the reported call-graph **coverage** — low coverage means more false positives.
- **`uml_callgraph`** (`scope: type:Name|module:Name`) — per-method fan-in/out, recursion, hot methods,
  coverage.
- **`uml_impact <type>`** — the blast radius (transitive dependents) of a type — "is this safe to
  change?" before you touch it.
- **`uml_check` (`rules:`)** — validate against an `architecture.yml` and get the pass/fail verdict
  with each violation's `file:line`.

## When to drop to the CLI

The MCP set is deliberately small and omits everything below — reach for the `uml` CLI (build first:
`swift build`, binary at `.build/debug/UMLCLI`) for these:

1. **See it** — `uml diagram --from a.json --package` / the class diagram (`--focus <Type>` to zoom a
   neighbourhood), and `uml image ... --output x.png` (macOS), then **read the PNG back as an image**.
   Visual review catches what metrics/source can't: hairballs, lopsided layouts, edges pointing "up"
   the layer stack, orphan nodes. The MCP exposes no rendering.
2. **Gate drift** — store a baseline, then `uml diff <old> <new> --format json` / `uml check
   --baseline <name>`; fail CI on adverse movement (fan-out creep, new cross-layer edge, new cycle).
3. **Gate architecture in CI** — `uml check --source . --rules architecture.yml` **fails the build**
   (non-zero exit); the MCP's `uml_check` only returns a verdict. Gate module cycles as a hard
   invariant.
4. **One-shot file audit** — `Scripts/audit.sh [SOURCE_DIR] [OUTPUT_DIR] [RULES_YAML]` analyzes once
   and fans every command out against that snapshot, writing `metrics.json`, `cycles.json`,
   `smells.json`, `deadcode.json`, `callgraph.json`, `doctor.json`, `package.dot`, `check.json`, PNGs.
5. **Extras with no MCP tool** — `uml call-cycles` (method-level SCCs / mutual recursion) and
   `uml enums` (enum-case inventory with associated values).

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
