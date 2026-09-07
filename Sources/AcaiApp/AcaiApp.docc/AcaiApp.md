# ``AcaiApp``

The Açaí application: explore a codebase, draw and edit diagrams, track findings, and compare
revisions — on macOS, iPad and iPhone.

## Overview

`AcaiApp` is one of the three entry points over [AcaiLibrary](/documentation/acailibrary/) —
alongside the [AcaiCLI](/documentation/acaicli/) tool and the [AcaiMCP](/documentation/acaimcp/)
server. It is a library target: both shipped apps are thin `@main` shells in `App/macOS` and
`App/iOS` that wrap the same `AcaiRootScene`, so one code base serves all three form factors.

Diagram geometry and the node views come from [AcaiRender](/documentation/acairender/) — which is why
what you see on the canvas matches what `acai image` renders headlessly. Repository access goes
through `AcaiGit`, a libgit2 wrapper.

## Getting a codebase in

A **project** groups codebases and diagrams; a **codebase** points at source and holds its index
state, file filter and quality configuration. There are two ways to add one, on every platform:

- **A local folder**, chosen through the system document picker. On iOS that reaches any file
  provider — iCloud Drive, Working Copy, and so on. Access is retained with a security-scoped
  bookmark, so it survives relaunches.
- **A GitHub repository**, cloned in-app. Sign in with the device flow (a short code plus a
  verification page — no client secret), then pick a repository. Cloning is a real git clone over
  HTTPS via libgit2; only the credential-free URL is persisted.

Repositories are cloned once into a shared hub and each codebase gets its own linked worktree, so
several codebases on one monorepo share a single object store at different commits.

If a local folder happens to be a git working directory with an `origin` remote, it is silently
upgraded to a repository-linked codebase so revision comparison works.

## Diagrams

Eight generated types: **class**, **sequence**, **state**, **package**, **call graph**, **module
coupling**, **hotspots**, and **cycles**. Each opens on an infinite, pannable canvas with manual node
positions that persist, fit-to-view, and full undo/redo.

The class diagram is the deepest. Its inspector covers:

- **Visibility** — properties, methods and enum cases, globally or overridden per type; a minimum
  access level.
- **Filter** — the same selector vocabulary the quality rules use, so a view you like can be saved
  as a named preset or promoted straight into a quality rule.
- **Relationships** — inheritance, composition and dependency edges, multiplicities, stereotypes.
- **Layout** — grouping by directory or product, and external types.
- **Focus** — centre on one type, limit the depth, choose direction and relationship kinds.

### The freeform editor

Beyond generated diagrams there is a freeform canvas: drag classes, actors, use cases, lifelines,
states, components, packages, databases and notes from a catalog and wire them up by hand. **Save as
Freeform** converts any generated diagram into an editable one — optionally carrying a read-only note
summarising its metrics. Named checkpoints snapshot a whole layout so you can explore and come back.

### Export

Diagrams export as **PNG**, **DOT** and **Mermaid**. Image export is what you see on screen: your
manual positions, sizes and visibility settings, rendered exactly as arranged.

## Findings and quality

Quality violations, dead-code candidates and parse diagnostics from every codebase merge into one
project-wide **Findings** list, sorted by severity and filterable by kind. Every row carries a
`file:line` and opens the source.

Suppressing a finding records it in a plain, versioned baseline file — a visible, reviewable decision
rather than a hidden toggle. The quality-check editor writes the same `quality.yml` the CLI reads,
and can export a ready-made CI invocation so the rules you tuned here gate your build.

## Comparing revisions

Any diagram can be compared against a **branch, tag, SHA or pull request**. Pull requests compare
against the merge base, so a moved base branch doesn't leak unrelated changes into the delta.

The comparison side is extracted read-only — the working tree, index and `HEAD` are never touched,
and no `git` executable is involved, so it behaves identically on iOS. Changed elements are
colour-coded and badged; the panel also lists changed files and the findings delta.

## Staying current

Local codebases are watched and reindexed automatically after a short debounce. GitHub-backed ones
are checked for a moved remote `HEAD` on a schedule. Types, diagrams and codebases are searchable
through quick-open (⌘K on macOS) and are mirrored into Spotlight, and Handoff lets you continue a
diagram on another device.

## Languages

The app ships in English, German and French, following the system language — there is no in-app
language setting, so switching language means switching it for Acai in System Settings (macOS) or
Settings › Acai (iOS).

Every interface string is an identifier (`View.<Type>.<ShortTitle>`) resolved through
`LocalizedStringResource.app(_:)` against `Resources/Localizable.xcstrings`, which holds all three
languages. Adding a string means adding it there in all three at the same time: `LocalizationCatalogTests`
fails on an identifier that is missing, unused, or untranslated, so translations cannot fall behind
the app. Content the parser produced — type names, signatures, paths, metric readouts — and anything
written into an export or a persisted name stays English in every language.

`GermanLayoutJourneyTests` walks the densest screens with the app launched in German, the longest of
the three, and fails on any label the layout truncates.

## Structure

Screens live under `Screens/`, one directory per feature area, each pairing a SwiftUI view with an
observable view model. Domain and persistence types live under `Models/` and `Persistence/`;
`GitHub/` holds the device-auth flow, cloning and worktree synchronisation. Projects, diagrams and
artifacts persist as per-file JSON, and export/import moves projects, layouts and rules between
machines — indexed artifacts and clones are deliberately left out, since both are regenerable.
