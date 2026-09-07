# Agent routine policy

`CLAUDE.md` is the project guidance: architecture, the language-agnostic boundary, style rules and
the user-facing quality bar. Read it first and follow it — especially the boundary rules and the ban
on static-function namespaces, which are the two things work gets rejected over here. This file only
adds what is specific to working autonomously.

## Eligible work

Issues labeled `agent-ready`. You pick from the title and the `area:` labels before you read the
body, so the areas matter:

**Prefer** `area:analysis`, `area:quality`, `area:testing`, `area:cli`, `area:diagrams`. These live
in the engine and the CLI, which you can build and test in full, so you can finish them in one run
and hand over something already verified. Parser fixes with a failing case, added test coverage,
refactors that remove a boundary violation, and corrections to diagram output are the sweet spot.

**Lower priority, not off limits** — `area:accessibility`, `area:platform`, and anything in
`AcaiApp`, `AcaiRender` or `AcaiGit`. These are macOS-only targets (`#if canImport(SwiftUI)` in
`Package.swift`), so they are absent from your Linux build and you cannot compile them, run them, or
look at them. That makes the loop slower and blinder, not impossible: CI's macOS jobs compile them
and the UI-test jobs run them on simulators, so you get real feedback on the next run — it just
costs a round trip per mistake instead of seconds.

Take one when the queue offers nothing from the preferred list, or when the issue names its files
and the change is small enough to reason about without running it. Say plainly in the PR body that
you could not build or see the change, and keep the diff small so a reviewer can check it by eye.

Two things genuinely need a human, so hand them back with a comment saying why:

- **Work judged by a screenshot.** The goldens under `App/AcaiUITests/__Snapshots__/` are LFS PNGs
  compared on simulators. You may still change code that shifts them, but you cannot regenerate or
  approve a golden — CI uploads its captures as artifacts for a person to inspect and accept.
- **Adding a language.** That is the `/add-language` skill's job and spans a new target, a parser, a
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

**Do not run `swiftlint analyze`, and do not act on its output.** `.swiftlint.yml` lists
`unused_import` and `unused_declaration` under `analyzer_rules`, but nothing runs them — not CI, not
you. They are unreliable here: `unused_import` names imports the compiler requires, and differs by
platform and even by Swift version, so acting on it breaks builds you cannot see. Removing unused
imports is not your work; leave those declarations and imports alone.

`swiftlint` here is a wrapper around the same pinned container CI uses, so its results match. If the
command is missing or the container fails to start, do not try to install SwiftLint yourself — say
in the PR body that you could not lint locally, and let CI's lint job report. Self-review against
`.swiftlint.yml` in that case: 120-column lines, 4-space indent, type nesting capped at 2,
cyclomatic complexity 10, file length 500, function body 50, type body 300. `--strict` promotes
every warning to an error, so one long line fails the build.

One thing no local gate covers: **the macOS-only targets.** Your Linux build skips `AcaiApp`,
`AcaiRender` and `AcaiGit` entirely, so a change to a shared type that breaks one of them compiles
clean for you and fails CI's `Unit Test macOS` job. Same for anything you write *inside* those
targets: CI is your only compiler there, exactly as it is for the other repositories in this setup.
Say so in the PR body when you touch them, and read `gh pr checks` on your next run
(`.github/workflows/build-test.yml`).

The UI-test jobs (iPhone, iPad, macOS) run on simulators against the LFS goldens, and they report
back to you like any other check. A failure there is worth reading rather than dismissing — but if
your change is engine-side and the diff is a rendered pixel, say so instead of guessing at the
canvas, and leave the golden for a human to accept.

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
