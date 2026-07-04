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

## One-shot

`Scripts/audit.sh [SOURCE_DIR] [OUTPUT_DIR] [RULES_YAML]` analyzes once and fans every command out
against that snapshot (via `--from`), writing `metrics.json`, `metrics.txt`, `cycles.json`,
`smells.json`, `deadcode.json`, `callgraph.json`, `call-cycles.json`, `doctor.json`, `inspect.json`,
`package.dot`, `check.json`, and PNGs. Or compose manually: `uml analyze <dir> --output a.json`,
then point any read-only command at `--from a.json` (one analysis pass, one consistent snapshot).
Build first: `swift build`, binary at `.build/debug/UMLCLI`.

## Strategies

1. **Make the intended architecture executable** — author/commit `architecture.yml` and run
   `uml check --source . --rules architecture.yml` (forbidden dependencies, `LayerRule`, `cycles`,
   `MetricBudget`s). Gate module cycles as a hard invariant; wire into CI (non-zero exit).
2. **Quantify responsibility bloat** — `uml metrics --from a.json --format human --sort fanOut|fanIn|weightedMethods|depthOfInheritance|numberOfChildren --top N`.
   High `fanOut` = too many collaborators (SRP risk); high `fanIn` = hub/change-magnet; high
   `weightedMethods` = god class. Triage the top outliers: split / extract / justify.
3. **Detect cycles** — `uml cycles --source . --scope modules|types|all`. Any multi-node SCC is a
   red flag; break it with dependency inversion / an extracted type.
4. **Read the diagrams** — `uml diagram --from a.json --package` (and the class diagram); look at
   where the arrows go: hub nodes, dense bidirectional clusters, edges pointing "up" the layer stack,
   orphan nodes. Use `--focus <Type>` to zoom a neighbourhood.
5. **See it** — `uml image ... --output x.png` (macOS), then **read the PNG back as an image**.
   Visual review catches what metrics/source can't (hairballs, layout/legibility defects).
6. **Gate drift** — store a baseline, then `uml diff <old> <new> --format json` / `uml check
   --baseline <name>`; fail CI on adverse movement (fan-out creep, new cross-layer edge, new cycle).

## Surface the parsed model (query commands)

Every command below emits JSON rows with `file:line` jump targets, so an agent gets precise targets
instead of a whole-graph dump. All take the shared `--from`/`--source`.

- **`uml inspect`** (alias `query`) — enumerate types **and** members, filtered by a type selector
  (`--kind`, `--module`, `--min-members`, `--stereotype`, …) plus member facets (`--member-kind`,
  `--min-parameters`, `--public-vars`, `--overrides`). The highest-leverage lookup: "which public
  classes have a 4+-parameter method?"
- **`uml smells`** — the code-smell detectors (long parameter lists, data classes, low cohesion,
  feature envy, deep nesting) ranked most-severe first, each with a fix hint. Thresholds default to a
  curated set; `--rules architecture.yml` reuses its `MetricBudget`s so a finding graduates into
  `check` unchanged.
- **`uml deadcode`** — methods no resolved call targets and that aren't entry points (public API,
  overrides, protocol requirements, or language markers). *Candidates*, not verdicts: always read the
  reported call-graph **coverage** — low coverage means more false positives.
- **`uml callgraph`** / **`uml call-cycles`** — per-method fan-in/out, recursion, hot methods and
  coverage; and method-level SCCs (mutual recursion).
- **`uml impact <Type>`** — the blast radius (transitive dependents) of a type — "is this safe to
  change?" before you touch it.
- **`uml doctor`** — parse-health trust score over parse diagnostics. **Run it first**: a low score
  means the rest of the audit is built on an incomplete parse and is correspondingly untrustworthy.
- **`uml enums`** — enum-case inventory with associated values.

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
