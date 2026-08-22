# ``AcaiApp``

The SwiftUI application shared by the macOS and iOS apps: explore a codebase, draw and edit
diagrams, track findings, and compare revisions.

## Overview

`AcaiApp` is one of the three entry points over [AcaiLibrary](/documentation/acailibrary/) —
alongside [AcaiCLI](/documentation/acaicli/) and [AcaiMCP](/documentation/acaimcp/). It is a
library target: both shipped apps are thin `@main` shells in `App/macOS` and `App/iOS` that wrap
the same `AcaiRootScene`, so one code base serves Mac, iPad and iPhone.

What it adds on top of the engine:

- **Projects and codebases** — a codebase points at a local folder or a repository cloned in-app,
  with its index state, file filter and quality configuration persisted alongside.
- **Eight diagram types** — class, sequence, state, package, call graph, module coupling, hotspots
  and cycles, each with its own inspector, filters and persisted manual layout.
- **A freeform editor** — drag types, actors, use cases, lifelines, states and notes onto an
  infinite canvas, or convert any generated diagram into an editable one.
- **Findings** — quality violations, dead-code candidates and parse diagnostics merged into one
  project-wide list, with suppressions recorded in a reviewable baseline.
- **Revision comparison** — diff a diagram against a branch, tag, SHA or pull request, extracted
  read-only so the working tree is never touched.
- **Metrics** — statistic cards, a churn-versus-complexity hotspot chart, and a main-sequence plot.

Diagram geometry and the node views come from [AcaiRender](/documentation/acairender/), which is why
what you see on the canvas matches what `acai image` renders. Repository access goes through
[AcaiGit](/documentation/acaigit/).

> Note: This page documents the app's *internals*. For what the app does from a user's point of
> view, see the [repository README](https://github.com/pauljohanneskraft/Acai#readme).

### Structure

Screens live under `Screens/`, one directory per feature area, each pairing a SwiftUI view with an
observable view model. Domain and persistence types live under `Models/` and `Persistence/`, and
`GitHub/` holds the device-auth flow, cloning and worktree synchronisation.
