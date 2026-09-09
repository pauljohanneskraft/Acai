# Agent routine policy

`CLAUDE.md` is the project guidance: architecture, the language-agnostic boundary, style rules and
the user-facing quality bar. Read it first and follow it — especially the boundary rules and the ban
on static-function namespaces, which are the two things work gets rejected over here. This file only
adds what is specific to working autonomously.

## Eligible work

Issues labeled `agent-ready`. You pick from the title and the `area:` labels before you read the
body, so the areas matter:

**Prefer** `area:analysis`, `area:quality`, `area:testing`, `area:cli`, `area:diagrams`. These live
in the engine and the CLI, which at least build on Linux, so CI's `Unit Test Linux` job gives you a
real answer on the next run instead of only the macOS jobs. Parser fixes with a failing case, added
test coverage, refactors that remove a boundary violation, and corrections to diagram output are the
sweet spot.

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

**You cannot build or test this project. CI is your only compiler.** The cloud environment is plain
Linux with no Swift toolchain, no SwiftLint and no Docker daemon — `command -v swift` finds nothing.
Do not try to install a toolchain, and do not spend a run trying to get one: `docker pull swift`
fails against this session's network policy, and building SwiftLint from source does not fit.

Say plainly in the PR body that you could not build, lint or test, and name what you checked
instead. Never imply a check you did not run. Every job in `.github/workflows/build-test.yml` —
`SwiftLint`, `Unit Test Linux`, `Unit Test macOS`, `Unit Test iOS`, and the three UI-test jobs — is
the first real compile your change sees.

Because CI is a slow gate, spend the effort a compiler would have caught:

- Read every API you call against its actual declaration, rather than assuming its shape. Missing
  arguments and wrong types are the failures that have actually cost round trips here.
- Check line length (120 columns), brace balance, and `.swiftlint.yml`'s limits by script: 4-space
  indent, type nesting capped at 2, cyclomatic complexity 10, file length 500, function body 50,
  type body 300, at most 5 function parameters. `--strict` promotes every warning to an error, so
  one long line fails the build.
- Grep the whole repository for every symbol you rename, move or delete before you push.

**Do not run `swiftlint analyze`, and do not act on its output.** `.swiftlint.yml` lists
`unused_import` and `unused_declaration` under `analyzer_rules`, but nothing runs them — not CI, not
you. They are unreliable here: `unused_import` names imports the compiler requires, and differs by
platform and even by Swift version, so acting on it breaks builds you cannot see. Removing unused
imports is not your work; leave those declarations and imports alone.

**The macOS-only targets are blind twice over.** `AcaiApp`, `AcaiRender` and `AcaiGit` are excluded
from any Linux build (`#if canImport(SwiftUI)` in `Package.swift`), so even a working toolchain
would not compile them. A change to a shared type that breaks one of them fails CI's
`Unit Test macOS` job and nothing earlier. Say so in the PR body when you touch them, and read the
checks on your next run.

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

## Review

Request review from `pauljohanneskraft` when a pull request is ready.

## Concurrency

No limit on open agent pull requests. Work existing ones first — red CI, then unaddressed review
comments, then incomplete drafts — but when every open agent PR is waiting on CI or on review, start
a new `agent-ready` issue rather than stopping. A new PR is better than no development.

This repository usually has several human PRs open (#146, #163). Those are not yours: they carry no
`agent-wip` issue link, and must not be touched.

## Human-set stop signs

`agent-blocked` on an issue or a pull request means hands off. Never add or remove it yourself.
