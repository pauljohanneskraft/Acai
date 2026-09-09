# Agent routine policy

`CLAUDE.md` is the project guidance: architecture, the language-agnostic boundary, style rules and
the user-facing quality bar. Read it first and follow it — especially the boundary rules and the ban
on static-function namespaces, which are the two things work gets rejected over here. This file only
adds what is specific to working autonomously.

## Eligible work

Issues labeled `agent-ready`. You pick from the title and the `area:` labels before you read the
body, so the areas matter:

**Every area is open to you.** CI covers the whole package, not just the parts that build on Linux:
`Unit Test macOS` runs `swift build` and `swift test --parallel` over everything including
`AcaiApp`, `AcaiRender` and `AcaiGit`; `Unit Test iOS` runs the package tests on a simulator; and
three UI-test jobs exercise the app itself against the screenshot goldens. So the app-side targets
are, if anything, better covered than the engine-only ones — there is no area you should avoid
because feedback would not reach you.

What differs between areas is not coverage but how *specific* the feedback is. A parser fix with a
failing case tells you exactly what broke; a layout change tells you a golden moved by 0.03%. Prefer
`area:analysis`, `area:quality`, `area:testing`, `area:cli` and `area:diagrams` when the queue offers
them, for that reason alone — not because the others are off limits.

The real constraint is the same everywhere: **you cannot compile anything locally**, so every mistake
costs a CI round trip rather than seconds. Keep diffs small, say in the PR body what you could not
check, and read the checks on your next run.

One thing genuinely needs a human, so hand it back with a comment saying why:

- **Adding a language.** That is the `/add-language` skill's job and spans a new target, a parser, a
  configuration, detectors, registration and the docs module map. Too large for one autonomous run.

Work judged by a screenshot **is** yours: when your change moves a golden, refresh it yourself — see
[Accepting screenshot goldens](#accepting-screenshot-goldens).

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

**Which job catches what.** `Unit Test Linux` builds and tests only the platform-agnostic targets —
`AcaiApp`, `AcaiRender` and `AcaiGit` are `#if canImport(SwiftUI)`-gated and absent there. Those are
covered by `Unit Test macOS`, which builds and tests the whole package, and by `Unit Test iOS` and
the UI-test jobs. So a change to a shared type that breaks an app-side target goes green on Linux and
red on macOS: when Linux passes, that is not the all-clear.

The UI-test jobs (iPhone, iPad, macOS) run on simulators against the committed goldens, and they
report back to you like any other check. A failure there is worth reading rather than dismissing.

### Accepting screenshot goldens

When your own change moves a golden, refresh it — do not hand that back. `Scripts/snapshots_accept.sh`
needs no simulator and no Xcode: it downloads the captures CI already uploaded and copies them over
the committed goldens, so it runs fine here.

```sh
Scripts/snapshots_accept.sh                 # newest Build & Test run for your branch
Scripts/snapshots_accept.sh <run-id>        # a specific run
git diff --stat -- App/AcaiUITests/__Snapshots__
```

Every run uploads its captures whether it passed or failed, so wait until the UI-test jobs have
**finished** — artifacts do not exist while a job is still queued or running. The CI job summary
carries a drift table naming exactly which state moved and by how much; read it before you accept
anything.

**The script copies every capture for all three platforms, so it will also overwrite goldens your
change had nothing to do with.** That is the one way this goes wrong: a rendering regression or a
simulator flake gets baked into the goldens and stops being visible to anyone. So after running it,
go through `git diff --stat` line by line and `git checkout --` every golden your diff does not
explain. Keep only the ones you can name a reason for.

If a golden moved and you cannot explain why from your own diff, that is a finding, not a refresh:
leave it alone and say so.

These PNGs are **not** in Git LFS — `.gitattributes` excludes `App/**/*.png` from the filter — so
they commit as ordinary binary files and need no `git lfs` step.

Commit refreshed goldens separately from code, with a message naming the states that moved, and say
in your hand-over which goldens you accepted and why, so the reviewer knows to look at the images.

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
