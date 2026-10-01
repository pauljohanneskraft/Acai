# ``AcaiCLI``

The `acai` command-line tool: analyze a codebase, draw diagrams, compute metrics, and gate
architecture in CI.

## Overview

`acai` is one of the three entry points over [AcaiLibrary](/documentation/acailibrary/) — alongside
the [AcaiMCP](/documentation/acaimcp/) server and the [AcaiApp](/documentation/acaiapp/) SwiftUI app.
This page is the complete flag-by-flag reference.

Everything here comes from the binary's own `--help`. Run `acai <command> --help` any time to check
against your build.

---

## Contents

- [Install](#Install)
- [The mental model](#The-mental-model)
- [Shared options](#Shared-options)
- Commands: [`analyze`](#analyze) · [`store`](#store) · [`list`](#list) · [`diagram`](#diagram) · [`image`](#image) · [`atlas`](#atlas) · [`metrics`](#metrics) · [`hotspots`](#hotspots) · [`quality`](#quality) · [`rules`](#rules) · [`inspect`](#inspect) · [`callgraph`](#callgraph) · [`dependents`](#dependents) · [`diff`](#diff)
- [Recipes](#Recipes)
- [Platform differences](#Platform-differences)

---

## Install

The primary path is Homebrew, tapping this repository directly (there's no separate tap repo):

```sh
brew tap pauljohanneskraft/acai https://github.com/pauljohanneskraft/Acai
brew install acai
```

This installs both `acai` and `acai-mcp` onto your `PATH`, for macOS (arm64 / x86_64) and Linux
(x86_64 / arm64). `brew upgrade acai` and `brew uninstall acai` work as usual. The formula
(`Formula/acai.rb`) downloads the matching prebuilt archive for your platform — it never builds
from source.

Without Homebrew, grab a prebuilt binary directly from every
[tagged release](https://github.com/pauljohanneskraft/Acai/releases) — each archive contains both
`acai` and `acai-mcp`:

| Asset | Platform |
| --- | --- |
| `acai-macos-arm64.tar.gz` | macOS, Apple silicon |
| `acai-macos-x86_64.tar.gz` | macOS, Intel |
| `acai-linux-x86_64.tar.gz` | Linux x86_64 |
| `acai-linux-arm64.tar.gz` | Linux arm64 |

Each ships a `.sha256` sibling.

```sh
tar -xzf acai-macos-arm64.tar.gz
sudo mv acai acai-mcp /usr/local/bin/
```

Contributors build from a checkout instead:

```sh
./Scripts/cli_create.sh     # swift build -c release --arch arm64
./Scripts/cli_install.sh    # onto your PATH
./Scripts/cli_uninstall.sh
```

---

## The mental model

Every analysis command needs **one artifact**, supplied one of two ways:

- `--source <dir>` — parse a directory now, or
- `--from <name-or-path>` — reuse a stored analysis, by name, by a `.json` artifact's path, or by the
  path of a source directory that already has one stored.

They're mutually exclusive, and one is required. Parsing a large repo repeatedly is wasteful, so the usual pattern is: **store once, query many times.**

```sh
acai store myproj ./MyProject        # parse once
acai metrics  --from myproj          # …then everything else is instant
acai quality  --from myproj --rules quality.yml
acai diagram  --from myproj --output arch.dot
```

A stored analysis is also your **baseline** for drift checks — see [`diff`](#diff) and `quality --baseline`.

> **Trust the parse first.** `acai analyze --health` scores how cleanly your code parsed. A low score means every metric, cycle and diagram built on it is unreliable. Run it before you act on anything else.
>
> You don't have to run it separately: `metrics`, `quality`, `callgraph`, `inspect`, `diff` and `dependents`
> each embed a compact `health` object (`score`, `diagnosticCount`, `countsByKind`) — the same shape
> `analyze --health` uses, without its full per-diagnostic list — in their `--format json` output, under
> a `health` key alongside the command's own data. `diff` combines both sides into the weaker-trust
> view. Below `HealthCheck.trustThreshold` (`0.8`), every command that loads an artifact (including
> `diagram`, which has no JSON output to embed a field in) also prints a one-line warning to stderr
> naming the diagnostic count and pointing at `acai analyze --health` for the list — piped stdout stays
> clean either way.

---

## Shared options

These appear on nearly every command.

### Artifact source

| Flag | Meaning |
| --- | --- |
| `--from <from>` | Name of a stored analysis, or path to a `.json` file or a source directory. |
| `--source <source>` | Path to a source directory to analyze on the fly. |
| `--language <language>` | Restrict analysis to one or more languages. Repeatable. |

`--language` accepts: `swift`, `kotlin`, `java`, `typescript`, `javascript`, `dart`, `python`, `c`, `cpp`. Repeat for several: `--language kotlin --language java`. Unknown values are rejected at parse time.

`--from` resolves in order: an existing `.json` file path; an existing directory, looked up in the
shared analysis store by its resolved path (this is how the CLI picks up an analysis the app or an MCP
session already produced for that directory, with no name needed); otherwise it's looked up as a name
under the store. An artifact written by an older Açaí version reports that it must be regenerated
rather than failing obscurely, and an artifact whose `schemaVersion` is newer than this build
understands reports the found and expected version numbers rather than misreading it.

### What gets parsed

Parsing a directory reads what the repository says it contains, not every byte under the path:

| Left out | Why |
| --- | --- |
| Anything a `.gitignore` excludes | The root file and every nested one are read, `!` negation rules included. A nested file overrides its parent for its own subtree, and — as in git — a negation cannot re-include a file inside an ignored directory. |
| A file over the per-file size ceiling | A bundled `.js`, a vendored single-file library or a generated file that escaped every exclusion would otherwise be read whole into memory. The default ceiling is 2 MiB. |
| Build-output and dependency directories | Each language contributes its own (`node_modules`, `Pods`, `target`, …), plus `.git` and hidden directories. |

A skipped file is not a silent one: it becomes a `skipped` parse diagnostic carrying its size, and a
`.gitignore` line that can't be read becomes an `invalidPattern` diagnostic naming the file and line.
Both are counted by [`analyze --health`](#analyze), so a type you expected to find and can't is
explained rather than simply absent.

**Symbolic links are followed.** A workspace that symlinks a shared package into place — common in
JavaScript monorepos and Bazel-style layouts — is analyzed rather than silently losing that
directory. Each directory is entered at most once however many links alias it, so a link pointing at
an ancestor terminates instead of looping, and linking a directory in yields the same artifact as
copying it in place.

### Output and formatting

| Flag | Values | Notes |
| --- | --- | --- |
| `--output <path>` | — | Writes to a file; prints to stdout if omitted. |
| `--format` | `human`, `json` | Default is `json` for `analyze --health`, `metrics`, `inspect`, `callgraph`, `dependents`; **`human`** for `quality` and `diff`. On `diagram` it means something else — `dot` or `mermaid`, inferred from `--output`'s extension and otherwise **`mermaid`**. |
| `--include-generated` | flag | Machine-generated types are **excluded by default**; this includes them. |

### Selector facets

`inspect` (and quality rules) filter types by these, all optional and AND-combined. A selector with no facets matches everything.

| Flag | Meaning |
| --- | --- |
| `--module <glob>` | Module/target name; supports `*` and `?`. |
| `--type <glob>` | Type id / qualified name glob. |
| `--kind <kind>` | `class`, `actor`, `struct`, `enum`, `protocol`, `interface`, `trait`, `typeAlias`, `object`, `extension`, `annotation`, `module`, `record`, `mixin` |
| `--min-access <level>` | `public`, `open`, `internal`, `protected`, `private`, `filePrivate`, `packagePrivate` |
| `--stereotype <name>` | UML stereotype, e.g. `entity`, `repository`. |
| `--annotation <name>` | Annotation marker, e.g. `Entity`. |
| `--min-members <n>` | Types with at least *n* members — finds god types. |
| `--min-nesting <n>` | Types nested at least *n* deep. |

### Class-diagram flags

Shared by `diagram` (and partly `image`). Only flags you actually pass are applied, so a `--config` file's values survive untouched.

| Flag | Values |
| --- | --- |
| `--direction` | `TB`, `LR`, `BT`, `RL` |
| `--group-by` | `file`, `namespace`, `none` |
| `--show-members` / `--no-show-members` | paired toggle |
| `--min-access <level>` | as above |
| `--show-external-types` | include referenced-but-undefined types as placeholders |
| `--no-infer-composition` | don't derive composition/aggregation from property types |
| `--no-infer-dependency` | don't derive dependency from parameter/return types |
| `--color-by <metric>` | colour nodes by a per-type metric's value, gradient endpoints from its `budgets` entry's `min`/`max` |
| `--rules <yaml>` | rules file supplying `--color-by`'s budget thresholds |

### Focus

Narrow a class diagram to one type's neighbourhood.

| Flag | Values |
| --- | --- |
| `--focus <type>` | The type to centre on. |
| `--focus-depth <n>` | `1` = the type plus direct neighbours. Omit for unlimited. |
| `--focus-direction` | `dependencies`, `dependents`, `both` |
| `--focus-relationship` | `inheritance`, `conformance`, `composition`, `aggregation`, `association`, `dependency`, `extension`, `nesting` — repeatable |
| `--no-focus-interconnections` | draw only the edges actually walked |

---

## Commands

### `analyze`

> Analyze source code and output the code model as JSON, or its parse health.

The full `CodeArtifact` as JSON — or, with `--health`, a trust score over parse diagnostics. Every
`CodeArtifact` carries a top-level `schemaVersion` integer, so a reader can tell which shape it's
looking at without guessing from a decode failure; a file written before this field existed reads as
`schemaVersion: 0`.

| Flag | Notes |
| --- | --- |
| `--from`, `--source`, `--language` | artifact source |
| `--health` | Report parse health instead of the model. |
| `--format` | `human` or `json` (default `json`) — health report only. |
| `--output` | file or stdout |
| `--include-generated` | |

`--health`'s diagnostics include `skipped` (a file over the size ceiling) and `invalidPattern` (a
`.gitignore` line no rule could be read from) alongside the parser's own `error`, `missing`,
`unresolvedReference` and `unreadable` — see [What gets parsed](#What-gets-parsed).

```sh
acai analyze --source . --health --format human    # run this first
acai analyze --source . --output model.json
```

### `store`

> Analyze source code and store the result under a given name.

```
acai store <name> <source-dir> [--language <language> ...]
```

| Flag | Notes |
| --- | --- |
| `--language` | Restrict analysis to one or more languages. Repeatable. |

Both arguments are positional. Writes `<name>.json` into the shared analysis store and prints the path.
The store also records the source directory's resolved path, so the same analysis is found — no
re-parsing needed — by an MCP session or the app pointed at that directory, and by `--from <source-dir>`
below. The stored `CodeArtifact` carries its `schemaVersion`, checked on every read.

```sh
acai store main-baseline ./MyProject
acai store mobile ./MyProject --language kotlin --language java
```

**Where it lands:** `~/.acai/analysis/` on macOS. On Linux it's `<documentDirectory>/analysis/`, falling back to a temporary directory if that can't be resolved.

### `list`

> List all stored analyses.

No options. Prints a `NAME · LANGUAGE · TYPES · FILES · PATH` table, or `No stored analyses found.` An
artifact that can't be decoded shows `(error reading)` rather than aborting the listing.

### `diagram`

> Generate a diagram (DOT or Mermaid) from an analysis or source directory.

The text-output workhorse. Renders a **class** diagram by default; one flag switches it to another family.

| Flag | Notes |
| --- | --- |
| `--from`, `--source`, `--language` | artifact source |
| `--format` | `dot`, `mermaid`. If omitted, inferred from `--output`'s extension (`.dot`/`.gv`: `dot`; `.mmd`/`.md`/`.mermaid`: `mermaid`); `mermaid` for any other extension or stdout. |
| `--theme` | `light`, `dark` |
| `--config <yaml>` | Lock options down in a file for repeatable output. |
| `--output` | Output file path; prints to stdout if omitted. |
| *class-diagram flags* | `--direction`, `--group-by`, `--show-members`/`--no-show-members`, `--min-access`, `--show-external-types`, `--no-infer-composition`, `--no-infer-dependency`, `--color-by`, `--rules` |
| *focus flags* | `--focus`, `--focus-depth`, `--focus-direction`, `--focus-relationship`, `--no-focus-interconnections` |
| `--sequence-from <entry>` | Sequence diagram from `"Type.method"`, or `"function"` for a top-level function. |
| `--map <A=B>` | Resolve a protocol/interface to a concrete type while tracing. Repeatable. |
| `--max-depth <n>` | Sequence call depth (default `5`). |
| `--state-from <var>` | State diagram for `"Type.variable"` or a global `"variable"`. |
| `--max-states <n>` | Fail beyond this many distinct states (default `20`). |
| `--package` | Package/module dependency diagram with coupling metrics. |
| `--module-coupling` | The same module graph as `--package`, labelled with each module's `Ca`/`Ce`/`I`/`A`/`D` and its main-sequence zone, with Stable-Dependencies-Principle breaches dashed. |
| `--call-graph` | Static call graph. |
| `--call-graph-scope <s>` | `type:Name` or `module:Name`. Whole codebase if omitted. |
| `--max-nodes <n>` | Fail a class, package or coupling diagram beyond this many nodes, naming the count (default `2000`). Narrow with `--focus` instead of raising it. |

```sh
acai diagram --source . --output arch.mmd
acai diagram --from myproj --output arch.dot
acai diagram --from myproj --format dot | dot -Tsvg -o arch.svg
acai diagram --from myproj --focus Playlist --focus-depth 2 --output playlist.mmd
acai diagram --from myproj --sequence-from "Checkout.placeOrder" --output checkout.mmd
acai diagram --from myproj --state-from "Download.state" --output states.mmd
acai diagram --from myproj --package --output modules.mmd
acai diagram --from myproj --module-coupling --output coupling.mmd
```

Mermaid embeds directly in Markdown — GitHub, most documentation sites and every Markdown preview
render it without anything installed. For Graphviz, write to a `.dot` file or pass `--format dot`,
which stdout needs, and render it anywhere Graphviz runs: `dot -Tpng arch.dot -o arch.png`. The
default matches `acai_diagram`'s on the MCP server.

> **`--theme default` still works**, on `diagram` and `image` alike. It is a deprecated spelling of
> `light` — accepted, hidden from `--help`, and due for removal in a later major release. The `theme:`
> key in a `--config` file takes either spelling too.

### `image`

> Render a class diagram to a PNG image (**macOS only**).

Same diagram families as `diagram`, rendered natively through SwiftUI instead of Graphviz — same layout engine and node views the app uses, so the output matches what you see on screen.

| Flag | Notes |
| --- | --- |
| `--from`, `--source`, `--language` | artifact source |
| `--output <path>` | **Required.** |
| `--grouping` | `none`, `directory`, `product` (default `product`) — note this differs from `diagram`'s `--group-by`. |
| `--min-access <level>` | Hides members *and whole types* below the level. |
| `--hide-members` | |
| `--scale <n>` | Resolution factor, default `2.0`. |
| `--theme` | `light` (default), `dark` |
| `--source-old` / `--from-old` | Render a **delta image** against this older side. |
| *diagram-kind + focus flags* | `--sequence-from`, `--map`, `--max-depth`, `--state-from`, `--max-states`, `--package`, `--module-coupling`, `--call-graph`, `--call-graph-scope`, `--focus`, `--focus-depth`, `--focus-direction`, `--focus-relationship`, `--no-focus-interconnections`, `--max-nodes` — as `diagram` |

```sh
acai image --source . --grouping directory --output arch.png
acai image --from myproj --min-access public --scale 3 --output api.png
acai image --source-old ./before --source ./after --output delta.png
```

### `atlas`

> Bundle a codebase's diagrams, statistics and findings into one PDF (**macOS only**).

The same document format as the app's Codebase Atlas export: a title page, one page per diagram, the statistics the codebase detail pane shows, and every quality violation, dead-code candidate and parse diagnostic. The diagram section is the default class diagram, package graph and call graph; a diagram that cannot be rendered gets a page saying so (and a warning on stderr) rather than failing the export.

| Flag | Notes |
| --- | --- |
| `--from`, `--source`, `--language` | artifact source |
| `--output <output>` | **Required.** Output PDF file path. |
| `--name <name>` | Name for the title page. Defaults to the analyzed directory's name. |
| `--rules <rules>` | Path to the YAML rules file the findings section is judged by. Defaults to the built-in curated smell budgets. |
| `--scale <scale>` | Output resolution scale factor for the embedded diagrams (default `2.0`). |
| `--theme <theme>` | Colour theme for the embedded diagrams: `light` (default), `dark`. |
| `--max-nodes <max-nodes>` | Maximum node count before a graph diagram's page reports it could not render (default `2000`). |

```sh
acai atlas --source . --output atlas.pdf
acai atlas --source . --output atlas.pdf --rules quality.yml --theme dark
```

The PDF carries a format marker (`Acai Codebase Atlas — Format 1`) on the title page and in its PDF metadata.

### `metrics`

> Compute static-analysis metrics (counts, coupling, OO metrics) as JSON.

| Flag | Notes |
| --- | --- |
| `--from`, `--source`, `--language` | artifact source |
| `--include-generated` | |
| `--format` | `json` (default), `human` |
| `--sort <metric>` | Ranking for the human tables. Default `fanOut`. |
| `--top <n>` | Limit the human type table. |
| `--output` | file or stdout |

`--sort` accepts: `fanOut`, `fanIn`, `weightedMethods`, `depthOfInheritance`, `numberOfChildren`, `responseForClass`, `publicMemberCount`, `publicMemberRatio`, `mutablePublicState`, `maxParameters`, `meanParameters`, `dataClassScore`, `overrideCount`, `nestingDepth`, `deepAndWide`, `lackOfCohesion`, `featureEnvyMethods`, `linesOfCode`.

**`linesOfCode`** is *physical* lines — every line from a declaration's first to its last, blanks and comments included. It is counted as a union of line ranges per file rather than a sum, so a nested type's lines are not charged again to the type that encloses it, and a type whose behaviour lives in extensions in other files is credited with those lines too. Module totals attribute each declaration to the file it was written in, so a cross-module extension counts toward the module that declares it. Per type it appears as the `loc` column and `TypeMetric.linesOfCode`; per module as the module table's `loc` and `ModuleCoupling.linesOfCode`; across the codebase as the summary's `Lines:` and `Counts.linesOfCode`, which also covers free functions, module-scope variables, and files in modules that declare no type of their own — so it can exceed the sum of the module rows.

`--format json` output: `{ "metrics": <CodeMetrics>, "health": <HealthCheck.Summary> }`.

```sh
acai metrics --from myproj --format human --sort weightedMethods --top 20
```

### `hotspots`

> Rank files by churn × complexity — where a refactoring budget buys the most (**macOS only**).

The classic hotspot technique: how often a file changes, against how complex its types are. A file
above both medians is a hotspot; the report ranks those by churn × complexity. Churn is a git-history
walk, so `--source` must point inside a git checkout — a plain folder is an error, not an empty list.

| Flag | Notes |
| --- | --- |
| `--source <path>` | **Required.** A directory inside a git checkout; may be a subdirectory of the repository root. |
| `--language <lang>` | Repeatable, as elsewhere. |
| `--include-generated` | |
| `--commits <n>` | How many commits of history to walk for churn. Default `50`. |
| `--top <n>` | Limit the ranked list. |
| `--format` | `human` (default), `json` |
| `--output <path>` | |

`--format json` output: `{ "churnThreshold": <median>, "complexityThreshold": <median>,
"commitWindow": <n>, "filesScored": <n>, "hotspotCount": <n>, "hotspots": [{ "path", "type",
"churn", "complexity", "score", "isHotspot" }] }`, ranked highest score first. `type` is the declared
type whose most complex method sets `complexity`, omitted for a file that declares none.
`hotspotCount` counts every file above both medians, even when `--top` lists fewer.

```sh
acai hotspots --source . --top 10
acai hotspots --source . --commits 200 --format json --output hotspots.json
```

### `quality`

> Check the codebase against a declarative code-quality rules file.

**The CI gate.** Validates the relationship graph and metrics against a YAML rules file and **exits non-zero** on any violation. Omit `--rules` to use the built-in curated smell budgets.

| Flag | Notes |
| --- | --- |
| `--from`, `--source`, `--language` | artifact source |
| `--rules <yaml>` | Rules file. Defaults to the built-in smell budgets. |
| `--explore` | Report findings but **always exit 0**, and additionally list dependency cycles. |
| `--scope` | `modules`, `types`, `all` (default) — cycle scope in explore mode. |
| `--baseline <name-or-path>` | Also report architectural drift since that baseline, and evaluate the rules file's `movements` (required if the rules file declares any). |
| `--format` | `human` (default), `json` |
| `--output` | file or stdout |

```sh
acai quality --source . --rules quality.yml              # gate: fails the build
acai quality --source . --explore                        # survey: never fails
acai quality --source . --rules quality.yml --baseline last-release
```

**The rules file.** Every top-level key is optional:

| Key | Shape |
| --- | --- |
| `forbidden` | list of `{from: Selector, to: Selector, kinds: [Kind]?, message: String?}` |
| `cycles` | `{scope: modules \| types}` |
| `budgets` | list of `{target: Selector?, metric: <name>, max: Double?, min: Double?, message: String?}` |
| `layers` | `{layers: [{name, selector}], allowSkip: Bool}` — ordered top to bottom, `allowSkip` defaults `true` |
| `contracts` | list of `{into: Selector, only: Selector, kinds: [Kind]?, message: String?}` |
| `movements` | list of `{target: Selector?, metric: <name>, minImprovement: Double?, message: String?}` — only evaluated with `--baseline` |
| `includeGeneratedTypes` | `Bool`, default `false` |

**Movements — proving a change moved the measurements the right way.** Given `--baseline`, each `movements` entry states how much a metric must have improved (decreased) since then; omitting `minImprovement` (or `0`) means "must not get worse". Every *other* metric on the same target is also checked for a silent regression, so an improvement bought by a hidden cost elsewhere doesn't pass — scope `target` to what the change actually touched to keep the check focused there instead of the whole codebase.

```yaml
movements:
  - target: { typeGlob: "OrderService" }
    metric: fanOut
    minImprovement: 2       # fanOut must have decreased by at least 2
  - target: { module: "Payments" }
    metric: distance         # no minImprovement: must simply not regress
```

**Budgetable metrics.** Module-scoped: `instability`, `abstractness`, `distance`, `publicApiSurface`. Type-scoped: `fanIn`, `fanOut`, `depthOfInheritance`, `weightedMethods`, `numberOfChildren`, `numberOfProperties`, `rfc`, `maxParameters`, `mutablePublicState`, `lcom`, `featureEnvyMethods`, `dataClassScore`, `nestingDepth`, `maxCyclomaticComplexity`, `linesOfCode` (see [`metrics`](#metrics) for what it counts).

**Scoping a budget to one language.** A type-scoped budget's `target` may carry a `language` (e.g. `swift`, `c`, `kotlin` — the same values as `--language`), so it only matches types parsed from that language. Omitted, the budget applies to every language, as before. This matters most for a metric a language without encapsulation can't mean the same thing by — C gives every struct field `.public` since it has no access-control keywords, so an unscoped `mutablePublicState` budget in a codebase with any C is set by C's meaningless maximum rather than the OO languages it's meant to protect. `acai rules` seeds one `mutablePublicState` hint per language present when the codebase has more than one, each `target`-scoped to it.

```yaml
budgets:
  - target: { language: swift }
    metric: mutablePublicState
    max: 0
```

Each breach carries a fix hint — `maxParameters` suggests a parameter object, `lcom` suggests splitting the type.

**Built-in defaults** (used when `--rules` is omitted): `maxParameters ≤ 5`, `dataClassScore ≤ 0.8`, `nestingDepth ≤ 2`, `lcom ≤ 1`, `featureEnvyMethods ≤ 2`, `maxCyclomaticComplexity ≤ 10`. `mutablePublicState` is deliberately left out — it's idiomatic in value types and would flood struct-heavy code.

This repository gates itself with its own [`quality.yml`](https://github.com/pauljohanneskraft/Acai/blob/main/quality.yml).

**Colouring a diagram by measurement.** `acai diagram --color-by <metric> --rules quality.yml` tints
each type-scoped node along a fine-to-critical gradient and prints the value next to it, so colour is
never the only signal. The gradient's endpoints are the metric's own `budgets` entry — `min` (or `0`
when unset) is "fine", `max` is "critical" — so a diagram's colours can never disagree with what
actually fails the build; there is exactly one place to change a metric's thresholds:

```yaml
budgets:
  - metric: maxCyclomaticComplexity
    max: 10
```

The colours themselves are fixed (green at `fine`, red at `critical`, amber between) and shared with
the rest of the app. `--color-by` requires a per-type metric with a `budgets` entry that sets `max`; a
module-scoped metric, or one with no such budget, is a validation error.

`--format json` output: `{ "quality": <QualityReport>, "drift": <ArtifactDiff>?, "health": <HealthCheck.Summary> }` (`drift` is present only with `--baseline`). `QualityReport` carries its own top-level `schemaVersion`, independent of the artifact's.

### `rules`

> Generate a candidate `quality.yml` from the current graph.

Seeds budgets from your current worst-case metrics, so adopting `quality` is "review and edit a draft" rather than "author from a blank page" — and the thresholds ratchet against regression from day one.

| Flag | Notes |
| --- | --- |
| `--from`, `--source`, `--language` | artifact source |
| `--output` | file or stdout |

```sh
acai rules --source . --output quality.yml
```

Review and tighten before committing.

### `inspect`

> Enumerate types and members as JSON/human, filtered by a selector.

Structured search — the answer to *"which public classes in module X have a method with four or more parameters?"* without grepping. Every row carries a `file:line`.

Takes all [selector facets](#Selector-facets) — `--module`, `--type`, `--kind`, `--min-access`, `--stereotype`, `--annotation`, `--min-members`, `--min-nesting` — plus member-level ones:

| Flag | Meaning |
| --- | --- |
| `--from`, `--source`, `--language` | artifact source |
| `--include-generated` | |
| `--member-kind` | `property`, `method`, `initializer`, `deinitializer`, `subscript` |
| `--min-parameters <n>` | Members with at least *n* parameters. |
| `--public-vars` | Only publicly-settable stored properties. |
| `--overrides` | Only members overriding an inherited member. |
| `--enums` | List enum cases with raw and associated values instead. |
| `--format` | `json` (default), `human` |
| `--output` | file or stdout |

```sh
acai inspect --from myproj --kind class --min-members 30 --format human
acai inspect --from myproj --min-access public --min-parameters 4
acai inspect --from myproj --enums
```

`--format json` output: `{ "types": [<TypeQuery.TypeRow>], "health": <HealthCheck.Summary> }`, or with
`--enums`: `{ "enums": [<EnumInventory.Entry>], "health": <HealthCheck.Summary> }`.

### `callgraph`

> Call-graph analysis: metrics, method cycles, or dead-code candidates.

`deadcode` reports members that no resolved call edge targets and that aren't reachable by contract —
public API, an override, a protocol requirement, or one of the language's entry-point markers. It scans
methods in every language; a language's initializers and subscripts are scanned only where its parser
records calls to them, since a kind whose callers are never recorded has no edge to be found by and
would report every declaration of it as uncalled. The report names the kinds it actually scanned: a
`Scanned:` line in human output, `scannedKinds` in JSON.

| Flag | Notes |
| --- | --- |
| `--from`, `--source`, `--language` | artifact source |
| `--include-generated` | |
| `--mode` | `metrics` (default), `cycles`, `deadcode` |
| `--scope` | `type:Name` or `module:Name` — metrics/cycles only. |
| `--format` | `json` (default), `human` |
| `--top <n>` | Limit the human metrics table to the hottest methods. |
| `--no-fail` | In `cycles` mode, exit 0 even when cycles are found. |
| `--output` | file or stdout |

```sh
acai callgraph --from myproj --mode metrics --format human --top 15
acai callgraph --from myproj --mode cycles              # non-zero exit on cycles
acai callgraph --from myproj --mode deadcode
```

> **Read the coverage figure in `deadcode` output.** It's the false-positive floor: methods reachable only through dynamic dispatch or reflection look uncalled to a static analyser. Treat the result as a candidate list, not a verdict.

`--format json` output wraps each mode's data alongside `health`: `{ "callGraph": <CallGraphMetrics.Report>, "health": ... }`, `{ "cycles": [<MethodCycles.Cluster>], "health": ... }`, or `{ "deadCode": <DeadCodeScan.Report>, "health": ... }`.

### `dependents`

> Show the transitive dependents (blast radius) of a type.

The type is a **positional argument**, not a flag.

```
acai dependents [options] <type>
```

| Flag | Notes |
| --- | --- |
| `--from`, `--source`, `--language` | artifact source |
| `--include-generated` | |
| `--depth <n>` | Limit reverse reachability to *n* hops. Unlimited if omitted. |
| `--format` | `json` (default), `human` |
| `--output` | file or stdout |

```sh
acai dependents --from myproj Playlist
acai dependents --from myproj --depth 2 --format human MediaItem
```

`--format json` output: `{ "impact": <ImpactAnalysis.Report>, "health": <HealthCheck.Summary> }` — the
key keeps its original name, so the output shape is unchanged by the rename.

> **`acai impact` still works.** It is a deprecated alias for `dependents` with identical behaviour and
> identical output, hidden from `--help` and due for removal in a later major release.

### `diff`

> Show the structural delta between two revisions of a codebase.

Reports only what structurally changed — added/removed types, added/removed/changed relationships, and notable metric movement.

Each side is a positional stored-analysis name or `.json` path, **or** a directory via `--source-old` / `--source-new`.

| Flag | Notes |
| --- | --- |
| `--source-old` / `--source-new` | Analyze a directory as that side. |
| `--language` | Restrict analysis to one or more languages. Repeatable. Applied to **both** sides analysed on the fly. |
| `--format` | `human` (default), `json` |
| `--diagram` | `dot` or `mermaid` — render a colour-coded delta diagram instead of a report. |
| `--sequence-from`, `--state-from`, `--package`, `--module-coupling`, `--call-graph`, `--call-graph-scope` | Pick the diagram family for `--diagram`. |
| `--max-depth <n>` | Sequence call depth (default `5`). |
| `--max-states <n>` | Fail beyond this many distinct states (default `20`). |
| `--include-generated` | Include machine-generated types in the analysis (default: they are excluded). Applied to **both** sides before diffing, so a generated type is never reported as added or removed by the filtering itself. |
| `--output` | file or stdout |

```sh
acai diff main-baseline --source-new ./                    # drift since a baseline
acai diff --source-old ./before --source-new ./after
acai diff old.json new.json --format json
acai diff --source-old ./before --source-new ./after --diagram dot --output delta.dot
```

Delta colouring: **added green, removed red, changed amber**, with `+` / `−` / `~` badges so status is never conveyed by colour alone. Class, package, coupling and call-graph deltas are coloured in both DOT and Mermaid; sequence and state deltas are coloured in DOT only, because Mermaid's syntax for those has no per-edge colour.

`--format json` output (non-`--diagram`): `{ "diff": <ArtifactDiff>, "health": <HealthCheck.Summary> }` —
`health` combines both sides into the weaker-trust view (the lower score, diagnostic counts summed).

---

## Recipes

**Gate architecture in CI.** A [GitHub Action](https://github.com/pauljohanneskraft/Acai) is
published from this repository — it downloads the matching release binary for the runner, so the
workflow doesn't install a toolchain or reinvent the invocation:

```yaml
- uses: pauljohanneskraft/Acai@v1.2.3    # pin to a released tag
  with:
    rules: quality.yml                   # optional; omit to use the built-in smell budgets
```

Every `acai quality` flag is available as an input — `source`, `baseline`, `format`, `output` — and
the rendered report comes back as the `report` output for a later step to post as a comment or
artifact. The action fails the job on any violation, the same as the underlying command's non-zero
exit; see [`action.yml`](https://github.com/pauljohanneskraft/Acai/blob/main/action.yml) for the
full input list.

On a CI system that isn't GitHub Actions, or once `acai` is already on `PATH` some other way, the
underlying command is just:

```yaml
- name: Acai quality check
  run: acai quality --source . --rules quality.yml
```

**Adopt quality rules on an existing codebase.**

```sh
acai rules --source . --output quality.yml        # draft from current state
$EDITOR quality.yml                               # tighten what you can
acai quality --source . --rules quality.yml       # now it ratchets
```

**Catch architectural drift in a pull request.**

```sh
acai store baseline ./main-checkout
acai diff baseline --source-new ./pr-checkout --format json --output drift.json
```

**Prove a refactor actually improved the metric it targeted.**

```sh
acai store baseline ./main-checkout
# quality.yml: { movements: [{ target: { typeGlob: "OrderService" }, metric: fanOut, minImprovement: 2 }] }
acai quality --source ./pr-checkout --rules quality.yml --baseline baseline
```

**Survey an unfamiliar codebase.**

```sh
acai analyze --source . --health --format human   # trustworthy parse?
acai store x . && acai metrics --from x --format human --sort fanOut --top 20
acai quality --from x --explore                   # ranked smells + cycles
acai image   --from x --grouping directory --output overview.png
```

**Check a refactor is safe.**

```sh
acai dependents --from x --format human LegacyService
acai callgraph --from x --mode deadcode
```

**Embed a diagram in Markdown.**

```sh
acai diagram --from x --format mermaid --focus Playlist --output docs/playlist.mmd
```

Mermaid renders natively on GitHub — paste the output into a ` ```mermaid ` fence.

---

## Platform differences

The CLI runs on macOS and Linux. **Two differences:** `image` and `atlas` are macOS-only because they render through SwiftUI's `ImageRenderer`, which needs a window-server session; `hotspots` is macOS-only because its churn walk goes through libgit2, which Açaí builds against SecureTransport/CommonCrypto and so links on Apple platforms only.

On Linux all three subcommands are **absent** — `acai --help` lists eleven subcommands rather than fourteen. Every other command and flag is identical. For images there, emit DOT and render with Graphviz:

```sh
acai diagram --source . --output arch.dot
dot -Tpng arch.dot -o arch.png
```

Stored analyses also live in different places per platform — see [`store`](#store).
