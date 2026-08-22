# ``AcaiCLI``

The `acai` command-line tool: analyze a codebase, draw diagrams, compute metrics, and gate
architecture in CI.

## Overview

`acai` is one of the three entry points over [AcaiLibrary](/documentation/acailibrary/) — the other
two being [AcaiMCP](/documentation/acaimcp/) and [AcaiApp](/documentation/acaiapp/). It exposes
twelve commands covering the whole engine:

- **Look around** — `analyze` (with `--health` for a parse-trust score), `inspect`, `impact`.
- **Draw** — `diagram` (DOT/Mermaid) and `image` (PNG, macOS only), covering class, package,
  sequence, state and call-graph views.
- **Measure** — `metrics`, `callgraph`.
- **Gate** — `quality` against a declarative `quality.yml`, and `rules init` to draft one.
- **Compare** — `diff` between two revisions, optionally as a colour-coded delta diagram.
- **Reuse** — `store` and `list` keep a parsed artifact around so later commands skip re-parsing.

> Note: This page documents the tool's *internals* — the `ParsableCommand` types and option groups.
> For using the tool, the full flag-by-flag reference lives in
> [`Documentation/CLI.md`](https://github.com/pauljohanneskraft/Acai/blob/main/Documentation/CLI.md)
> in the repository, and `acai --help` is always authoritative for your build.

### Command structure

Every analysis command takes its input one of two ways, and they are mutually exclusive:
`--source <dir>` parses a directory now, `--from <name-or-path>` reuses a stored analysis or a
`.json` artifact. Shared behaviour lives in the option groups (`ArtifactSource`, `SelectorOption`,
`ClassDiagramFlags`, …) so a flag means the same thing everywhere it appears.

`image` is compiled only on macOS, where [AcaiRender](/documentation/acairender/) is available; on
Linux the subcommand is absent rather than failing at runtime.
