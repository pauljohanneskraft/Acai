# Agent routine policy

`CLAUDE.md` is the project guidance: architecture, the language-agnostic boundary, style rules and
the user-facing quality bar. Read it first and follow it — especially the boundary rules and the ban
on static-function namespaces, which are the two things work gets rejected over here. This file only
adds what is specific to working autonomously.

## Eligible work

Issues labeled `agent-ready`. You pick from the title and the `area:` labels before you read the
body, so the areas matter:

**Good fits** — `area:analysis`, `area:quality`, `area:testing`, `area:cli`, `area:diagrams`. These
live in the engine and the CLI, which you can build and test in full. Prefer parser fixes with a
failing case, added test coverage, refactors that remove a boundary violation, and corrections to
diagram output.

**Hand these back** — anything you cannot compile or see:

- `area:accessibility`, and `area:platform` work that touches the app. `AcaiApp` is macOS-only
  (`#if canImport(SwiftUI)` in `Package.swift`), so it is not in your Linux build at all. VoiceOver,
  Dynamic Type, Reduce Motion, iPad interactions, drag-and-drop, widgets and window management all
  need a running app on a real platform.
- Anything whose acceptance is a **screenshot**. The UI-test goldens under
  `App/AcaiUITests/__Snapshots__/` are LFS-tracked PNGs compared on simulators; you can neither
  produce nor judge them.
- `AcaiRender` and `AcaiGit` changes. Both are macOS-only targets (see `Package.swift`) — `AcaiGit`
  compiles libgit2 from source and exists for `AcaiApp` alone.
- Adding a language. That is the `/add-language` skill's job and spans a new target, a parser, a
  configuration, detectors, registration and the docs module map. Too large for one autonomous run.

Do not add third-party dependencies.

## Verification

**You can build and test this project.** The cloud environment has a Swift 6.2 toolchain, and the
package builds on Linux — CI proves it with a dedicated `Unit Test Linux` job. Run these before every push, from the repository root:

```sh
swiftlint lint --strict     # if the command exists — see below
swift build
swift test --parallel
```

Fix what they report. Do not push a red build: unlike the other repositories in this setup, you have
no excuse for handing a reviewer something that does not compile.

### Analyzer rules

`.swiftlint.yml`'s `analyzer_rules` (`unused_import`, `unused_declaration`) run only under
`swiftlint analyze`. CI's `SwiftLint` job runs the whole sweep, so a violation you leave behind
fails the build. Check the target you changed before pushing:

```sh
Scripts/analyze.sh AcaiCore    # ~17s per target
Scripts/analyze.sh             # every target, as CI does
```

It exits non-zero on any violation and prints a per-target summary. Use it rather than calling
`swiftlint analyze` yourself: it scopes the build to one target, which is what keeps the run in
seconds instead of half an hour, and it refuses to report a clean result from a build that compiled
nothing — the failure mode that otherwise makes analyze pass without checking anything.

**Treat every violation as a claim to check, not an instruction.** `unused_import` is wrong often —
in one sweep, 10 of 79 macOS violations named imports the compiler actually required, and half the
Linux violations named imports macOS needs. So: remove the import, then rebuild that target. If the
build fails, restore it and move on. Never remove a batch without a build in between.

**You run on Linux; CI also builds on macOS.** The two disagree about imports — `Foundation` is
frequently reported unused on Linux in files where macOS needs it for `URL`. Lines carrying
`// swiftlint:disable:next unused_import` were established that way and must stay. When your own
removal is flagged clean here but you cannot rule out macOS needing it, say so in the PR body
rather than assuming the Linux result settles it.

`unused_declaration` is switched off in `.swiftlint.yml` and must stay off: it cannot see a call
through a protocol witness, so every `CallSiteResolving` conformance in the language plugins reads
as unused. Do not re-enable it, and do not delete a declaration because some other tool calls it
dead.

CI fails on any violation, so they do have to be resolved — but a false positive is resolved by
keeping the code and marking the line, not by deleting something that was in use.

`swiftlint` here is a wrapper around the same pinned container CI uses, so its results match. If the
command is missing or the container fails to start, do not try to install SwiftLint yourself — say
in the PR body that you could not lint locally, and let CI's lint job report. Self-review against
`.swiftlint.yml` in that case: 120-column lines, 4-space indent, type nesting capped at 2,
cyclomatic complexity 10, file length 500, function body 50, type body 300. `--strict` promotes
every warning to an error, so one long line fails the build.

The `analyzer_rules` in `.swiftlint.yml` (`unused_import`, `unused_declaration`) run only under
`swiftlint analyze`, which needs a compiler log. Neither you nor CI runs it, so nothing catches an
import a refactor left behind — check that by eye.

One thing no local gate covers: **the macOS-only targets.** Your Linux build skips `AcaiApp`,
`AcaiRender` and `AcaiGit` entirely, so a change to a shared type that breaks one of them compiles
clean for you and fails CI's `Unit Test macOS` job. When you touch a type those targets consume, say
so in the PR body, and read `gh pr checks` on your next run
(`.github/workflows/build-test.yml`).

The UI-test jobs (iPhone, iPad, macOS) run on simulators against those LFS goldens. They are outside
what you can influence; if one fails on your PR and your change is engine-side, say so rather than
guessing at the canvas.

## Conventions

Beyond CLAUDE.md's style section, the two that bite hardest:

- **Never use a type as a static-function namespace.** Put the behaviour on a value, or in an
  extension on the type it belongs to. CLAUDE.md calls this non-negotiable.
- **No agnostic target may name a language.** `AcaiCore`, `AcaiDiagram`, `AcaiRender` and
  `AcaiLibrary`'s agnostic surface must not switch over `SourceLanguage` or carry per-language
  tables. Language data belongs in that language's plugin and reaches the engine by injection.

If you add a module, add it to the module map in
`Sources/AcaiLibrary/AcaiLibrary.docc/AcaiLibrary.md` — a generated page nothing links to is
unreachable.

## Concurrency

One agent PR in flight at a time. This repository usually has several human PRs open; those are not
yours, do not count against the limit, and must not be touched.
