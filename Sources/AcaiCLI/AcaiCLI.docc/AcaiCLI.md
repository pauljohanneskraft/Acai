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
- Commands: [`analyze`](#analyze) · [`store`](#store) · [`list`](#list) · [`diagram`](#diagram) · [`image`](#image) · [`metrics`](#metrics) · [`quality`](#quality) · [`rules init`](#rules-init) · [`inspect`](#inspect) · [`callgraph`](#callgraph) · [`impact`](#impact) · [`diff`](#diff)
- [Recipes](#Recipes)
- [Platform differences](#Platform-differences)

---

## Install

Prebuilt binaries are attached to every [tagged release](https://github.com/pauljohanneskraft/Acai/releases) — each archive contains both `acai` and `acai-mcp`:

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

From source:

```sh
./Scripts/cli_create.sh     # swift build -c release --arch arm64
./Scripts/cli_install.sh    # onto your PATH
./Scripts/cli_uninstall.sh
```

---

## The mental model

Every analysis command needs **one artifact**, supplied one of two ways:

- `--source <dir>` — parse a directory now, or
- `--from <name-or-path>` — reuse a stored analysis (by name) or a `.json` artifact (by path).

They're mutually exclusive, and one is required. Parsing a large repo repeatedly is wasteful, so the usual pattern is: **store once, query many times.**

```sh
acai store myproj ./MyProject        # parse once
acai metrics  --from myproj          # …then everything else is instant
acai quality  --from myproj --rules quality.yml
acai diagram  --from myproj --output arch.dot
```

A stored analysis is also your **baseline** for drift checks — see [`diff`](#diff) and `quality --baseline`.

> **Trust the parse first.** `acai analyze --health` scores how cleanly your code parsed. A low score means every metric, cycle and diagram built on it is unreliable. Run it before you act on anything else.

---

## Shared options

These appear on nearly every command.

### Artifact source

| Flag | Meaning |
| --- | --- |
| `--from <from>` | Name of a stored analysis, or path to a `.json` file. |
| `--source <source>` | Path to a source directory to analyze on the fly. |
| `--language <language>` | Restrict analysis to one or more languages. Repeatable. |

`--language` accepts: `swift`, `kotlin`, `java`, `typescript`, `javascript`, `dart`, `python`, `c`, `cpp`. Repeat for several: `--language kotlin --language java`. Unknown values are rejected at parse time.

`--from` resolves in order: an existing file path wins; otherwise it's looked up as a name under the stored-analysis directory. An artifact written by an older Açaí version reports that it must be regenerated rather than failing obscurely.

### Output and formatting

| Flag | Values | Notes |
| --- | --- | --- |
| `--output <path>` | — | Writes to a file; prints to stdout if omitted. |
| `--format` | `human`, `json` | Default is `json` for `analyze --health`, `metrics`, `inspect`, `callgraph`, `impact`; **`human`** for `quality` and `diff`. On `diagram` it means something else — `dot` or `mermaid`. |
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

The full `CodeArtifact` as JSON — or, with `--health`, a trust score over parse diagnostics.

| Flag | Notes |
| --- | --- |
| `--from`, `--source`, `--language` | artifact source |
| `--health` | Report parse health instead of the model. |
| `--format` | `human` or `json` (default `json`) — health report only. |
| `--output` | file or stdout |
| `--include-generated` | |

```sh
acai analyze --source . --health --format human    # run this first
acai analyze --source . --output model.json
```

### `store`

> Analyze source code and store the result under a given name.

```
acai store <name> <source-dir> [--language <language> ...]
```

Both arguments are positional. Writes `<name>.json` into the stored-analysis directory and prints the path.

```sh
acai store main-baseline ./MyProject
acai store mobile ./MyProject --language kotlin --language java
```

**Where it lands:** `~/.acai/analysis/` on macOS. On Linux it's `<documentDirectory>/analysis/`, falling back to a temporary directory if that can't be resolved.

### `list`

> List all stored analyses.

No options. Prints a `NAME · LANGUAGE · TYPES · FILES` table, or `No stored analyses found.` An artifact that can't be decoded shows `(error reading)` rather than aborting the listing.

### `diagram`

> Generate a diagram (DOT or Mermaid) from an analysis or source directory.

The text-output workhorse. Renders a **class** diagram by default; one flag switches it to another family.

| Flag | Notes |
| --- | --- |
| `--format` | `dot` (default), `mermaid` |
| `--theme` | `default`, `dark` |
| `--config <yaml>` | Lock options down in a file for repeatable output. |
| *class-diagram flags* | `--direction`, `--group-by`, `--show-members`/`--no-show-members`, `--min-access`, `--show-external-types`, `--no-infer-composition`, `--no-infer-dependency` |
| *focus flags* | `--focus`, `--focus-depth`, `--focus-direction`, `--focus-relationship`, `--no-focus-interconnections` |
| `--sequence-from <entry>` | Sequence diagram from `"Type.method"`, or `"function"` for a top-level function. |
| `--map <A=B>` | Resolve a protocol/interface to a concrete type while tracing. Repeatable. |
| `--max-depth <n>` | Sequence call depth (default `5`). |
| `--state-from <var>` | State diagram for `"Type.variable"` or a global `"variable"`. |
| `--max-states <n>` | Fail beyond this many distinct states (default `20`). |
| `--package` | Package/module dependency diagram with coupling metrics. |
| `--call-graph` | Static call graph. |
| `--call-graph-scope <s>` | `type:Name` or `module:Name`. Whole codebase if omitted. |

```sh
acai diagram --source . --output arch.dot
acai diagram --from myproj --format mermaid --output arch.mmd
acai diagram --from myproj --focus Playlist --focus-depth 2 --output playlist.dot
acai diagram --from myproj --sequence-from "Checkout.placeOrder" --output checkout.dot
acai diagram --from myproj --state-from "Download.state" --output states.dot
acai diagram --from myproj --package --output modules.dot
```

Render DOT anywhere Graphviz runs: `dot -Tpng arch.dot -o arch.png`.

### `image`

> Render a class diagram to a PNG image (**macOS only**).

Same diagram families as `diagram`, rendered natively through SwiftUI instead of Graphviz — same layout engine and node views the app uses, so the output matches what you see on screen.

| Flag | Notes |
| --- | --- |
| `--output <path>` | **Required.** |
| `--grouping` | `none`, `directory`, `product` (default `product`) — note this differs from `diagram`'s `--group-by`. |
| `--min-access <level>` | Hides members *and whole types* below the level. |
| `--hide-members` | |
| `--scale <n>` | Resolution factor, default `2.0`. |
| `--theme` | `default` (light), `dark` |
| `--source-old` / `--from-old` | Render a **delta image** against this older side. |
| *diagram-kind + focus flags* | as `diagram` |

```sh
acai image --source . --grouping directory --output arch.png
acai image --from myproj --min-access public --scale 3 --output api.png
acai image --source-old ./before --source ./after --output delta.png
```

### `metrics`

> Compute static-analysis metrics (counts, coupling, OO metrics) as JSON.

| Flag | Notes |
| --- | --- |
| `--format` | `json` (default), `human` |
| `--sort <metric>` | Ranking for the human tables. Default `fanOut`. |
| `--top <n>` | Limit the human type table. |

`--sort` accepts: `fanOut`, `fanIn`, `weightedMethods`, `depthOfInheritance`, `numberOfChildren`, `responseForClass`, `publicMemberCount`, `publicMemberRatio`, `mutablePublicState`, `maxParameters`, `meanParameters`, `dataClassScore`, `overrideCount`, `nestingDepth`, `deepAndWide`, `lackOfCohesion`, `featureEnvyMethods`.

```sh
acai metrics --from myproj --format human --sort weightedMethods --top 20
```

### `quality`

> Check the codebase against a declarative code-quality rules file.

**The CI gate.** Validates the relationship graph and metrics against a YAML rules file and **exits non-zero** on any violation. Omit `--rules` to use the built-in curated smell budgets.

| Flag | Notes |
| --- | --- |
| `--rules <yaml>` | Rules file. Defaults to the built-in smell budgets. |
| `--explore` | Report findings but **always exit 0**, and additionally list dependency cycles. |
| `--scope` | `modules`, `types`, `all` (default) — cycle scope in explore mode. |
| `--baseline <name-or-path>` | Also report architectural drift since that baseline. |
| `--format` | `human` (default), `json` |

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
| `includeGeneratedTypes` | `Bool`, default `false` |

**Budgetable metrics.** Module-scoped: `instability`, `abstractness`, `distance`, `publicApiSurface`. Type-scoped: `fanIn`, `fanOut`, `depthOfInheritance`, `weightedMethods`, `numberOfChildren`, `numberOfProperties`, `rfc`, `maxParameters`, `mutablePublicState`, `lcom`, `featureEnvyMethods`, `dataClassScore`, `nestingDepth`, `maxCyclomaticComplexity`.

Each breach carries a fix hint — `maxParameters` suggests a parameter object, `lcom` suggests splitting the type.

**Built-in defaults** (used when `--rules` is omitted): `maxParameters ≤ 5`, `dataClassScore ≤ 0.8`, `nestingDepth ≤ 2`, `lcom ≤ 1`, `featureEnvyMethods ≤ 2`, `maxCyclomaticComplexity ≤ 10`. `mutablePublicState` is deliberately left out — it's idiomatic in value types and would flood struct-heavy code.

This repository gates itself with its own [`quality.yml`](https://github.com/pauljohanneskraft/Acai/blob/main/quality.yml).

### `rules init`

> Generate a candidate `quality.yml` from the current graph.

The only nested subcommand. Seeds budgets from your current worst-case metrics, so adopting `quality` is "review and edit a draft" rather than "author from a blank page" — and the thresholds ratchet against regression from day one.

```sh
acai rules init --source . --output quality.yml
```

Review and tighten before committing.

### `inspect`

> Enumerate types and members as JSON/human, filtered by a selector.

Structured search — the answer to *"which public classes in module X have a method with four or more parameters?"* without grepping. Every row carries a `file:line`.

Takes all [selector facets](#Selector-facets), plus member-level ones:

| Flag | Meaning |
| --- | --- |
| `--member-kind` | `property`, `method`, `initializer`, `deinitializer`, `subscript` |
| `--min-parameters <n>` | Members with at least *n* parameters. |
| `--public-vars` | Only publicly-settable stored properties. |
| `--overrides` | Only members overriding an inherited member. |
| `--enums` | List enum cases with raw and associated values instead. |

```sh
acai inspect --from myproj --kind class --min-members 30 --format human
acai inspect --from myproj --min-access public --min-parameters 4
acai inspect --from myproj --enums
```

### `callgraph`

> Call-graph analysis: metrics, method cycles, or dead-code candidates.

| Flag | Notes |
| --- | --- |
| `--mode` | `metrics` (default), `cycles`, `deadcode` |
| `--scope` | `type:Name` or `module:Name` — metrics/cycles only. |
| `--top <n>` | Limit the human metrics table to the hottest methods. |
| `--no-fail` | In `cycles` mode, exit 0 even when cycles are found. |

```sh
acai callgraph --from myproj --mode metrics --format human --top 15
acai callgraph --from myproj --mode cycles              # non-zero exit on cycles
acai callgraph --from myproj --mode deadcode
```

> **Read the coverage figure in `deadcode` output.** It's the false-positive floor: methods reachable only through dynamic dispatch or reflection look uncalled to a static analyser. Treat the result as a candidate list, not a verdict.

### `impact`

> Show the transitive dependents (blast radius) of a type.

The type is a **positional argument**, not a flag.

```
acai impact [options] <type>
```

| Flag | Notes |
| --- | --- |
| `--depth <n>` | Limit reverse reachability to *n* hops. Unlimited if omitted. |
| `--format` | `json` (default), `human` |

```sh
acai impact --from myproj Playlist
acai impact --from myproj --depth 2 --format human MediaItem
```

### `diff`

> Show the structural delta between two revisions of a codebase.

Reports only what structurally changed — added/removed types, added/removed/changed relationships, and notable metric movement.

Each side is a positional stored-analysis name or `.json` path, **or** a directory via `--source-old` / `--source-new`.

| Flag | Notes |
| --- | --- |
| `--source-old` / `--source-new` | Analyze a directory as that side. |
| `--format` | `human` (default), `json` |
| `--diagram` | `dot` or `mermaid` — render a colour-coded delta diagram instead of a report. |
| `--sequence-from`, `--state-from`, `--package`, `--call-graph`, `--call-graph-scope` | Pick the diagram family for `--diagram`. |

```sh
acai diff main-baseline --source-new ./                    # drift since a baseline
acai diff --source-old ./before --source-new ./after
acai diff old.json new.json --format json
acai diff --source-old ./before --source-new ./after --diagram dot --output delta.dot
```

Delta colouring: **added green, removed red, changed amber**, with `+` / `−` / `~` badges so status is never conveyed by colour alone. Class, package and call-graph deltas are coloured in both DOT and Mermaid; sequence and state deltas are coloured in DOT only, because Mermaid's syntax for those has no per-edge colour.

---

## Recipes

**Gate architecture in CI.**

```yaml
- name: Acai quality check
  run: acai quality --source . --rules quality.yml
```

**Adopt quality rules on an existing codebase.**

```sh
acai rules init --source . --output quality.yml   # draft from current state
$EDITOR quality.yml                               # tighten what you can
acai quality --source . --rules quality.yml       # now it ratchets
```

**Catch architectural drift in a pull request.**

```sh
acai store baseline ./main-checkout
acai diff baseline --source-new ./pr-checkout --format json --output drift.json
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
acai impact --from x --format human LegacyService
acai callgraph --from x --mode deadcode
```

**Embed a diagram in Markdown.**

```sh
acai diagram --from x --format mermaid --focus Playlist --output docs/playlist.mmd
```

Mermaid renders natively on GitHub — paste the output into a ` ```mermaid ` fence.

---

## Platform differences

The CLI runs on macOS and Linux. **One difference:** `image` is macOS-only, because it renders through SwiftUI's `ImageRenderer`, which needs a window-server session.

On Linux the subcommand is **absent** — `acai --help` lists eleven subcommands rather than twelve. Every other command and flag is identical. For images there, emit DOT and render with Graphviz:

```sh
acai diagram --source . --output arch.dot
dot -Tpng arch.dot -o arch.png
```

Stored analyses also live in different places per platform — see [`store`](#store).
