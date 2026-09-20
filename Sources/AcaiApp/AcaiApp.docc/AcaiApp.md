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
state, file filter and quality configuration. There are three ways to add one, on every platform:

- **A local folder**, chosen through the system document picker. On iOS that reaches any file
  provider — iCloud Drive, Working Copy, and so on. Access is retained with a security-scoped
  bookmark, so it survives relaunches. Dragging one or more folders from Finder or Files onto a
  project in the sidebar adds them too, each named after its folder; a folder the project already
  has is skipped.
- **A remote URL** — any git remote reachable over HTTPS, whoever hosts it: GitLab, Bitbucket,
  Gitea, a self-hosted server. Its branches and tags are read before anything is cloned. Public
  repositories need no account; an address carrying credentials is refused rather than stored.
- **A GitHub repository**, picked from your account. Sign in with the device flow (a short code
  plus a verification page — no client secret), then pick a repository. This is a convenience on
  top of the remote URL path, not a separate one: the stored model is just the remote's
  credential-free URL, and the GitHub token is only ever sent to GitHub.

Cloning is a real git clone over HTTPS via libgit2. Repositories are cloned once into a shared hub
and each codebase gets its own linked worktree, so several codebases on one monorepo share a single
object store at different commits. **Pull** and the branch/tag picker work for every remote. Deleting
the last codebase that uses a repository deletes its clone too.

When GitHub reports a repository larger than about 500 MB, adding it asks first and offers **Clone
Latest Snapshot** — only the tip commit — alongside the full history. A latest-snapshot clone is
badged as such. Features that need history never present a truncated one as complete: the hotspot
chart and change-request comparisons say the history isn't there yet and offer **Fetch Full
History**, which deepens the shared clone in place. Remotes that don't report a size clone as before,
without asking.

If a local folder happens to be a git working directory with an `origin` remote, it is silently
upgraded to a repository-linked codebase so revision comparison works. Such a folder can also be
**analysed at another branch or tag** from the codebase header: that revision's tree is read from
the repository's history into a temporary directory, so the checkout, index, `HEAD` and any
uncommitted work are never touched. The header says which revision is analysed and what is checked
out, and View Source shows files as they were at that revision.

Finishing a codebase's first index adds a **guided route** card to the codebase screen: three stops
assembled entirely from measurements the index already took — where execution enters, the type most
other code depends on, and the type carrying the single most complex method — each opening the
diagram that actually shows it. **Hide** puts it away for good; **Guided Route** in the codebase's
header brings it back.

## Diagrams

Seven generated types: **class**, **sequence**, **state**, **package**, **call graph**, **module
coupling**, and **hotspots**. Each opens on an infinite, pannable canvas with manual node positions
that persist, fit-to-view, and full undo/redo. A dependency cycle — flagged wherever one is named,
such as a Quality Check or Findings row — opens as a class or package diagram scoped to just its
members and the edges that form it, rather than as a diagram type of its own.

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
manual positions, sizes and visibility settings, rendered exactly as arranged. On macOS an export
opens a save panel; on iPhone and iPad it opens the system share sheet, with Save to Files among
its options.

## Findings and quality

Quality violations, dead-code candidates and parse diagnostics from every codebase merge into one
project-wide **Findings** list, sorted by severity and filterable by kind. Every row carries a
`file:line` and opens the source.

Suppressing a finding records it in a plain, versioned baseline file — a visible, reviewable decision
rather than a hidden toggle. The quality-check editor writes the same `quality.yml` the CLI reads,
and can export a ready-made CI invocation so the rules you tuned here gate your build.

## Comparing revisions

Any diagram can be compared against a **branch, tag, SHA or open change request**. Change requests
come from the remote's host — GitHub today — for a cloned repository and for a local folder
tracking one alike. Each change request in the picker shows its title, who raised it, and which
branch merges into which. A change
request compares against the merge base, so a moved base branch doesn't leak unrelated changes into
the delta.

The comparison side is extracted read-only — the working tree, index and `HEAD` are never touched,
and no `git` executable is involved, so it behaves identically on iOS. Changed elements are
colour-coded and badged; the panel also lists changed files and the findings delta.

## Search

Types, diagrams and codebases are searchable through quick-open — ⌘L on macOS and on an iPad with a
hardware keyboard, the search field atop the sidebar otherwise. ⌘/ lists every shortcut the app binds.

## Links

Every project, codebase and diagram has a stable address that opens it directly, from a note, a chat
message or another app:

| Opens | Address |
| --- | --- |
| A project | `acai://project/<id>` |
| A codebase | `acai://codebase/<id>` |
| A diagram, generated or freeform | `acai://diagram/<id>` |

`<id>` is the item's UUID, which never changes, so a link survives renaming. **Copy Link** in any
project, codebase or diagram's context menu (or **File › Copy Link**, ⌥⌘C, on macOS for whatever is
selected) puts its address on the clipboard. If a link names something that has since been deleted,
or isn't an Açaí link at all, the app says so and stays where it was.

## Windows

On macOS, **Open in New Window** in a project, codebase or diagram's context menu (or **File › Open
in New Window**, ⌥⌘O, for the selection) gives it a window of its own. Each window navigates
independently; what you select in one doesn't move another. Windows reopen where they were after a
relaunch.

A diagram is shown by one window at a time, since each window edits its own copy of it. Opening a
diagram that another window already shows brings that window to the front, and selecting it in a
second window offers **Show Window** instead of a copy that could overwrite the first window's edits.

## Automation

**Reindex Codebase** is a Shortcuts action, so a reindex can be scheduled or chained into your own
automation, such as reindexing after a nightly merge. The run shows in the activity list like one you
started by hand. The action returns the codebase when the reindex finishes. It fails with the reason
when the codebase no longer exists, the analysis fails, or the run is cancelled, so a shortcut can
branch on the result.

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
`Remote/` holds the host-neutral remote model, cloning and worktree synchronisation; `GitHub/` holds
only what GitHub adds on top — the device-auth flow, repository browsing and change requests. Projects, diagrams and
artifacts persist as per-file JSON, and export/import moves projects, layouts and rules between
machines — indexed artifacts and clones are deliberately left out, since both are regenerable.
