# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Swift 6 SwiftPM package that parses source code in eight languages and emits UML class diagrams in DOT/Graphviz format. Shipped as a CLI (`AcaiCLI` → `acai`) and a macOS 15+ SwiftUI app (`AcaiApp`).

## Commands

- Build: `swift build`
- Test: `swift test --parallel`
- Single test: `swift test --filter AcaiKotlinTests` (target) or `--filter AcaiKotlinTests/SomeTest/testCase`
- Lint: `swiftlint lint --strict` (also handles formatting — there is no separate formatter)

Release binaries are **not** plain `swift build` — use the scripts in `Scripts/` (they build `-c release --arch arm64` and assemble the `.app` bundle): `cli_create.sh`, `cli_install.sh`, `app_create.sh`, `app_install.sh` (+ matching `*_uninstall.sh`).

## Before a change is done

1. `swiftlint lint --strict` passes (CI enforces this; opt-in + analyzer rules are on).
2. `swift test --parallel` passes.

Linux must keep building, but that's verified by CI only — no local Linux gate. Be mindful that `AcaiApp` is macOS-only (`#if canImport(SwiftUI)` in `Package.swift`) and the app scripts use macOS tools (`sips`, `iconutil`).

## Architecture

Layered, one module per concern (see `Package.swift`):

- `AcaiCore` — the **language-agnostic engine**: data models, the enrichment pipeline, project discovery (`BuildSystemDetector`, `ProjectDiscovery`, `FallbackDetector`, `SourceSpec`), `AnalysisService` (orchestration), and the language abstractions. `CodeParser` is the parser protocol (`language`, `fileExtensions`, `parse(source:fileName:)`, `configuration`). `CodeArtifact.SourceLanguage` is an **open `RawRepresentable<String>` struct** with no built-in constants (each language defines its own). `LanguageConfiguration` carries a language's quirks; `LanguageRegistry` maps a language to its configuration.
- `AcaiTreeSitter` — shared Tree-sitter helpers, re-exports `SwiftTreeSitter`.
- Per-language plugins, each depending on `AcaiCore` (+ `AcaiTreeSitter` for non-Swift) and **self-contained** (parser + its `SourceLanguage` constant + `LanguageConfiguration` + its build-system detector(s)): `AcaiSwift` (SwiftSyntax; SPM/Xcode detectors), `AcaiJS` (TS + JS; Node detector), `AcaiJVM` (Java **and** Kotlin in one target because they share the JVM build systems + `JVMBuildSystemDetector`), `AcaiDart` (Flutter detector), `AcaiPython` (`PythonDetector` for `pyproject.toml`/`setup.py`; vendors the grammar's `scanner.c` via the `CPythonScanner` target — see `Package.swift`), `AcaiCFamily` (C **and** C++ in one target — same rationale as `AcaiJVM`: they share the C/C++ build systems + `CFamilyBuildSystemDetector` and most of the grammar; `CCodeParser` owns `.c`/`.h` and content-sniffs each `.h` to route C++ headers to the C++ grammar). All non-Swift parsers are Tree-sitter.
- `AcaiDiagram` — DOT/Graphviz + Mermaid generation. Agnostic: it receives a `LanguageConfiguration` (via `ClassDiagramOptions.language`) rather than knowing any language.
- `AcaiLibrary` — the **composition root** (the only target that names the built-in languages). It depends on the language plugins, wires them into `AnalysisService.standard`, and `@_exported import`s `AcaiCore`/`AcaiDiagram` + the plugins so a single `import AcaiLibrary` surfaces everything.
- `AcaiCLI`, `AcaiApp` — entry points; depend on `AcaiLibrary` (not the individual plugins).

## The language-agnostic boundary (issue #69)

This separation is load-bearing — keep it:

- **No agnostic target may name or special-case a language or framework.** No `switch` over `SourceLanguage`, no hardcoded type-name tables, generated-file heuristics, or framework annotations in `AcaiCore`/`AcaiDiagram`/`AcaiRender`/`AcaiLibrary`'s agnostic surface. Such data lives in a parser's `LanguageConfiguration` and reaches the engine only by **parameter injection** (resolved from the `LanguageRegistry`, keyed on `artifact.metadata.sourceLanguage`).
- `SourceLanguage` has **no built-in constants in AcaiCore** — `.swift`, `.dart`, … are defined as extensions in their plugins, so an agnostic target literally cannot compile a reference to a specific language, and an external consumer adds a language from the outside the same way the built-ins do.
- There is **no empty-`LanguageConfiguration` default** on any engine API: every real language has a non-empty config, so the config is a required parameter (an empty default would silently mis-classify). Tests opt into an explicit fixture.
- `Modifier` and `TypeKind` stay **closed enums** by design — they are a shared vocabulary the diagram layer consumes exhaustively (this is the "sometimes a closed enum is right" case).
- **Language is per *file*, not per source-spec.** `AnalysisService.parseSpec` groups a spec's parsed files by each file's own `metadata.sourceLanguage` (a parser may report a different language than the extension that discovered it — e.g. `AcaiCFamily`'s C parser owns `.h` but reports `cpp` for a C++ header) and enriches each group with *that* language's configuration from the `LanguageRegistry`. This stays agnostic — keyed on the artifact's metadata, naming no language.

## Style

- 4-space indentation, 120-column lines (`.swiftlint.yml`).
- Type nesting capped at 2 levels; cyclomatic complexity warns at 10.
- Parsers are stateless `struct`s conforming to `CodeParser`.
- **NEVER use a type as a static-function namespace — not on a caseless `enum`, and not on a `struct`/`class` either.** A `static func` with no instance to act on is a global function in disguise, which is a code smell in this OO codebase. This is non-negotiable. Put the behavior **on a value** instead: model it as a real type you instantiate and call instance methods on (e.g. `Glob("a*").matches(x)`, `StronglyConnectedComponents(adjacency: g).cycles`, `DeltaEdgeColors.standard.hex(for: status)`), or as a computed property / method in an `extension` on the type the behavior belongs to (e.g. `relationship.diffKey`, `member.diffSignature`). A `static let`/`static var` that vends a configured **instance** of the type (like `ModuleResolver.standard`) is fine — that's a value, not a namespace. Free functions are likewise disallowed.
- Keep code documentation to an absolute minimum. Only add a comment when the information is genuinely useful and can't be inferred from the surrounding code or file — most code needs none. If a good name, a type signature, or something an IDE/LSP already surfaces (e.g. "who calls this," "this isn't private") would tell the reader the same thing, skip the comment; don't restate what the identifier already says. A comment describes the current state of the code, never its history (no "used to be X", "added for Y", "previously Z").

## Documentation

`Scripts/docs_generate.sh` reads the target list from the package manifest, so **every non-test target is published automatically** — library, executable and C targets alike. A module with no public API yields an empty page, which is fine; a module with no page at all is not.

**A generated page is not a reachable page.** When you add a module, also add it to the module map in `Sources/AcaiLibrary/AcaiLibrary.docc/AcaiLibrary.md` — that file is the site's landing page (`docs_generate.sh` redirects the root to it), and it is the only thing linking the per-module pages together. Skipping this leaves the docs reachable only by guessing the URL. Cross-module links there are written `[AcaiFoo](/documentation/acaifoo/)`, lowercased, no hosting base path (the renderer prepends it).

**All prose lives in `.docc` catalogs** — there are no per-module `README.md` files and no `Documentation/` folder. That includes the user-facing guides for the binaries: the full `acai` flag reference is `Sources/AcaiCLI/AcaiCLI.docc/AcaiCLI.md`, the MCP tool/schema reference is `Sources/AcaiMCP/AcaiMCP.docc/AcaiMCP.md`, and the app's is `Sources/AcaiApp/AcaiApp.docc/AcaiApp.md`. The root `README.md` links to their published pages rather than restating them; the only other markdown in the repo is `Examples/README.md`. Regenerate the CLI flag tables from `acai <command> --help`, never by hand from the source.

**In-page anchor links follow DocC's convention, not GitHub's.** DocC keeps the heading's case and turns spaces into hyphens (`## The mental model` → `#The-mental-model`); GitHub lowercases. A table of contents copied from GitHub-style markdown will silently fail to resolve, so match the heading exactly.

README screenshots live in `.github/images/`.

## Adding a language

Use the `/add-language` skill. A language is a self-contained plugin: a new target (dep + parser), its `SourceLanguage` constant + `CodeParser.configuration` (primitives/collections, any framework stereotypes or generated-code filter, build-output dirs), its build-system detector(s), then registration in `AcaiLibrary` (`AnalysisService.standard`). Do **not** add language data to any agnostic target. Finish by linking the new module from the AcaiLibrary module map — see [Documentation](#documentation).

## The user-facing quality bar

Architecture rules are above; these are the properties every feature must have. They are the things
that get silently skipped under time pressure, so they are the definition of done, not a polish pass.

**Concurrency and responsiveness.** Anything that can exceed ~100ms — network, file I/O, git,
parsing, rendering a large diagram — runs off the main actor, following the existing `Task.detached`
idiom rather than a second concurrency style. Off the main thread is not the same as visible: every
such operation needs a signal at its point of initiation and, if the user might navigate away, an
entry in the global activity list. Every user-initiated async action needs a cancellation path whose
underlying work actually observes cancellation — a Cancel button that only stops updating the UI is
lying. Dismissing a sheet with in-flight work cancels that work. Re-validate identifiers after every
`await` that crosses user-mutable state (look up by stable id again; never trust a pre-`await`
index). Debounce anything triggered by fast repeated input.

**Loading, empty, error.** Every screen showing a list or derived data designs all three, not just
the happy path: a progress indicator rather than a blank that reads as "no data"; a specific,
actionable empty state with the next action as a button, never a bare "No items"; and an error with
a retry in the same place it appears.

**Errors and confirmations.** Errors surface through the existing alert mechanism — never an empty
`catch`, never console-only, never "nothing happened". Every thrown error carries a specific
`errorDescription` a non-technical user could act on. Distinguish offline (retry when connectivity
returns) from a rejected/rate-limited API response (say when it resets) from an unexpected internal
failure (generic frame, specific detail in a disclosure). Destructive actions get a confirmation
naming the item and its specific consequence, plus "This cannot be undone" — unless a discoverable
undo exists, in which case say so instead of demanding a modal.

**Persistence.** Every shipped `Codable` model is a migration constraint: a new field must decode
from already-persisted data lacking it, and a removed one is decoded-and-discarded for a release
rather than dropped. Writes are atomic. Multi-step operations complete into a staging form and swap
in only on full success — a partial failure leaves what was there untouched. Every export/import
format carries a version marker from day one.

**Security.** Secrets live in Keychain, never in `UserDefaults`, a plain file, or persisted app
state, and are never logged or placed in a URL. Any path or archive entry built from external input
is validated against path-escape and symlink attacks before anything is written. User-supplied globs
and regular expressions are validated and bounded — a malformed pattern is an inline error, never a
hang or a crash.

**Interruption.** Relaunching returns the user where they were. An operation interrupted by
termination leaves recoverable state, and the app either resumes it or says it didn't finish —
never presents stale data as current. Purge rendered-image and measurement caches under memory
pressure before anything user-visible degrades.

**Accessibility.** Never encode meaning in colour alone — status needs a badge, shape or label
alongside it. Every interactive element has a label stating what it does; no element is more
informative visually than to VoiceOver. Every custom-drawn canvas element has an explicit
accessibility representation — left to default behaviour over a `Path`, it is invisible. Tap targets
are at least 44×44pt, padded rather than shrunk. Dynamic Type is verified at the largest
accessibility sizes, not merely compiled at the default. Animated pan/zoom/transition honours Reduce
Motion. Increased Contrast and Reduce Transparency are verified, not assumed. Full keyboard
navigation with a visible focus ring on macOS and iPad. Every new interactive element gets an
accessibility identifier in the same change that builds it.

**Consistency.** Icon-only is permitted for canvas-viewport toolbar actions, always with `.help()`
on macOS and a full label everywhere; anything in a `Form`, `List`, context menu or dialog uses icon
*and* label; primary calls-to-action are text-first. One term per concept: "Reindex" not
refresh/rescan; "Delete" not "Remove" in user-facing text; Project and Codebase keep their exact
meanings; "Diagram" means a generated or freeform diagram specifically, not a report or dashboard.
Every action gets a context menu on every platform, plus a swipe action for destructive or
high-frequency row actions on touch, plus a keyboard shortcut on pointer platforms following system
conventions. A feature reachable by exactly one path on one platform is not done. Sheets set initial
focus deliberately and order fields for sensible Tab traversal.

**Visual and motion.** One spacing scale, not per-view magic numbers. A small reused set of
animation curves, not a bespoke spring per surface. Every custom colour has an explicitly verified
dark-appearance value. Haptics for a small, consistent set of events. One loading-placeholder style
app-wide.

**Localization.** The app ships in English, German and French. No hardcoded user-facing strings — every
one goes into `Sources/AcaiApp/Resources/Localizable.xcstrings` as it is written, in all three
languages, and reaches the interface as `.app("Identifier")`, never as a bare literal. No manual
pluralization, and no hand-built date, number or byte-size formatting. Layouts tolerate strings longer
than the English source, and use leading/trailing rather than left/right throughout. The rules are in
[Writing a user-facing string](#Writing-a-user-facing-string).

**Network.** Debounce anything that triggers a request from typing. Handle rate limiting explicitly,
stating when it resets. Every call has a timeout and a bounded, backoff-based retry policy, and
non-idempotent operations are never retried silently.

**Privacy and licensing.** Every new persisted field is a privacy-surface change until shown
otherwise. Every new dependency gets a licence check before merge — noting whether it requires a
notice or full licence text — and anything touching networking or cryptography has its
export-compliance implications re-checked rather than assumed unchanged.

**Platform specifics.** iOS/iPadOS: standard navigation containers, safe areas respected except
where a full-bleed canvas genuinely requires otherwise, SF Symbols only. iPad: verify sidebar and
inspector layouts at narrow multitasking widths, and verify that any shortcut defined "for macOS"
also fires with an external keyboard. macOS: every toolbar action, context-menu action and "open
elsewhere" action has a menu-bar equivalent; settings live in the `Settings` scene; every icon-only
button has a tooltip.

## Writing a user-facing string

Every string the interface shows is an identifier resolved against `AcaiApp`'s String Catalog:

```swift
Text(.app("View.ClassDiagramSidebar.ShowProperties"))
Button(.app("View.ProjectDetailView.Delete"), role: .destructive) { … }
.help(.app("View.CallGraphSidebar.ExportDiagramImage"))
```

`.app(_:)` (`Sources/AcaiApp/Localization/LocalizedStringResource+App.swift`) binds `Bundle.module`,
which a bare `LocalizedStringKey` would not: `AcaiApp` is a package library, so an unbound key looks
in the *app* bundle and silently renders the identifier.

- **Identifiers are `View.<TypeName>.<ShortTitle>`** in PascalCase — `View.` only for a `View`,
  `ViewModifier` or `Scene`; a model or error type uses `<TypeName>.<Case>` (`DiagramType.CallGraph`,
  `Finding.Severity.Critical`). They are stable: rewording the English never changes the identifier,
  and the same English word in two places gets two identifiers so it can be translated two ways.
- **The English lives in the catalog, not at the call site.** `Localizable.xcstrings` is the single
  source of truth for `en`, `de` and `fr`, and every identifier carries all three — an identifier
  with a missing language reaches users as raw text, which is what `LocalizationCatalogTests` fails
  on.
- **Interpolate after the identifier**, in argument order: `.app("View.Foo.Found \(count)")` looks up
  `View.Foo.Found %lld`, whose value places the `%lld` wherever that language needs it.
- **Plurals are catalog `variations`**, never `count == 1 ? … : …` and never `"item(s)"`. German is
  `one`/`other`; French puts 0 *and* 1 in `one`. A string carrying two counts needs `substitutions`,
  one per count, so each agrees independently.
- **One term per concept, per language.** The same English string gets the same translation
  everywhere, and a family of related names is translated as a family — all the `DiagramType` names
  are German, so `Call Graph` is `Aufrufgraph`, not left English beside `Klassendiagramm`. Keeping
  an English word is fine when it is what developers in that language actually say (`Codebase`,
  `Repository`, `Hotspots`), as long as every sibling makes the same choice.
  `LocalizationCatalogTests` enforces both rules; a deliberate loanword diagram name is declared in
  its `loanwordDiagramNames` list.
- **Content is not chrome.** Type names, member signatures, file paths, coordinates, sizes, metric
  readouts and anything else the parser produced are never translated: write `Text(verbatim:)`, or a
  `format:` initializer for a number. So are strings that leave the app — persisted diagram names,
  the exported codebase atlas, CLI/MCP output — which is why `DiagramType` and `Finding` keep an
  English `displayName`/`label` alongside their localized `title`.
- **`AcaiCore`, `AcaiGit`, `AcaiDiagram` are not localized** — they are shared with the CLI and MCP
  server. An error thrown from them is presented in a localized frame with its own text shown
  untranslated as detail.
- Only Swift Build (Xcode) compiles `.xcstrings`, so a plain `swift build`/`swift test` leaves
  identifiers unresolved. Don't put a chrome view in a `Tests/AcaiAppTests` render snapshot; screens
  are covered by the journey tests, which run the real, Xcode-built app.

## Testing

Four suites, each catching what the others structurally cannot: **unit tests** (logic, fast,
SwiftPM); **render snapshot tests** (does a flat component still look right, light and dark);
**journey tests** (does a real flow work end to end in the real app process, and does a full screen
still look right); and **guardrail tests** (does a surface meet the bar every surface owes).

**Prefer automation over driving the app by hand.** An agent clicking through a simulator from
screenshots is slow and fails silently when it misreads one; a journey checks the same behaviour
unattended with a deterministic result. A missing screen accessor, fixture path or injection seam is
the next piece of the testing system to build — not a reason to fall back to manual verification.
Manual testing is legitimate only for what genuinely cannot be automated yet.

**Render snapshots have a hard scope limit, discovered empirically.** Off-screen rendering has no
real window server, so it cannot resolve AppKit-backed controls, materials, or a live
measurement→layout feedback loop — and it fails by producing *wrong pixels*, not by throwing, so a
passing test is not evidence. This layer is therefore limited to flat, pre-laid-out, materials-free
component views. Anything touching `TextField`, `Form`, `List` or system materials belongs in a
journey test instead. Before adding a view here, look at the recorded image, not just the result.

**Determinism comes from injection seams, not from the network.** Unit tests stub HTTP with the
established `URLProtocol` pattern. Journeys select pre-seeded state via a launch argument and swap in
fixture conformances for account, repository and analysis work, so a journey never depends on real
network or real parsing unless proving exactly that. Poll conditions rather than sleeping before
asserting; a raised timeout is not a fix for a flaky async test.

**Added in the same change, never as follow-up**: a screen object for a new screen, an accessibility
identifier and real label for every new interactive element, and the loading/loaded/error identifier
triple for every new async operation reachable from a journey. Coverage that is always one change
behind the app never catches up.
