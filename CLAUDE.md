# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Swift 6 SwiftPM package that parses source code in five languages and emits UML class diagrams in DOT/Graphviz format. Shipped as a CLI (`UMLCLI` → `uml`) and a macOS 15+ SwiftUI app (`UMLApp`).

## Commands

- Build: `swift build`
- Test: `swift test --parallel`
- Single test: `swift test --filter UMLKotlinTests` (target) or `--filter UMLKotlinTests/SomeTest/testCase`
- Lint: `swiftlint lint --strict` (also handles formatting — there is no separate formatter)

Release binaries are **not** plain `swift build` — use the scripts in `Scripts/` (they build `-c release --arch arm64` and assemble the `.app` bundle): `cli_create.sh`, `cli_install.sh`, `app_create.sh`, `app_install.sh` (+ matching `*_uninstall.sh`).

## Before a change is done

1. `swiftlint lint --strict` passes (CI enforces this; opt-in + analyzer rules are on).
2. `swift test --parallel` passes.

Linux must keep building, but that's verified by CI only — no local Linux gate. Be mindful that `UMLApp` is macOS-only (`#if canImport(SwiftUI)` in `Package.swift`) and the app scripts use macOS tools (`sips`, `iconutil`).

## Architecture

Layered, one module per concern (see `Package.swift`):

- `UMLCore` — the **language-agnostic engine**: data models, the enrichment pipeline, project discovery (`BuildSystemDetector`, `ProjectDiscovery`, `FallbackDetector`, `SourceSpec`), `AnalysisService` (orchestration), and the language abstractions. `CodeParser` is the parser protocol (`language`, `fileExtensions`, `parse(source:fileName:)`, `configuration`). `CodeArtifact.SourceLanguage` is an **open `RawRepresentable<String>` struct** with no built-in constants (each language defines its own). `LanguageConfiguration` carries a language's quirks; `LanguageRegistry` maps a language to its configuration.
- `UMLTreeSitter` — shared Tree-sitter helpers, re-exports `SwiftTreeSitter`.
- Per-language plugins, each depending on `UMLCore` (+ `UMLTreeSitter` for non-Swift) and **self-contained** (parser + its `SourceLanguage` constant + `LanguageConfiguration` + its build-system detector(s)): `UMLSwift` (SwiftSyntax; SPM/Xcode detectors), `UMLJS` (TS + JS; Node detector), `UMLJVM` (Java **and** Kotlin in one target because they share the JVM build systems + `JVMBuildSystemDetector`), `UMLDart` (Flutter detector). All non-Swift parsers are Tree-sitter.
- `UMLDiagram` — DOT/Graphviz + Mermaid generation. Agnostic: it receives a `LanguageConfiguration` (via `ClassDiagramOptions.language`) rather than knowing any language.
- `UMLLibrary` — the **composition root** (the only target that names the built-in languages). It depends on the language plugins, wires them into `AnalysisService.standard`, and `@_exported import`s `UMLCore`/`UMLDiagram` + the plugins so a single `import UMLLibrary` surfaces everything.
- `UMLCLI`, `UMLApp` — entry points; depend on `UMLLibrary` (not the individual plugins).

## The language-agnostic boundary (issue #69)

This separation is load-bearing — keep it:

- **No agnostic target may name or special-case a language or framework.** No `switch` over `SourceLanguage`, no hardcoded type-name tables, generated-file heuristics, or framework annotations in `UMLCore`/`UMLDiagram`/`UMLRender`/`UMLLibrary`'s agnostic surface. Such data lives in a parser's `LanguageConfiguration` and reaches the engine only by **parameter injection** (resolved from the `LanguageRegistry`, keyed on `artifact.metadata.sourceLanguage`).
- `SourceLanguage` has **no built-in constants in UMLCore** — `.swift`, `.dart`, … are defined as extensions in their plugins, so an agnostic target literally cannot compile a reference to a specific language, and an external consumer adds a language from the outside the same way the built-ins do.
- There is **no empty-`LanguageConfiguration` default** on any engine API: every real language has a non-empty config, so the config is a required parameter (an empty default would silently mis-classify). Tests opt into an explicit fixture.
- `Modifier` and `TypeKind` stay **closed enums** by design — they are a shared vocabulary the diagram layer consumes exhaustively (this is the "sometimes a closed enum is right" case).

## Style

- 4-space indentation, 120-column lines (`.swiftlint.yml`).
- Type nesting capped at 2 levels; cyclomatic complexity warns at 10.
- Parsers are stateless `struct`s conforming to `CodeParser`.

## Adding a language

Use the `/add-language` skill. A language is a self-contained plugin: a new target (dep + parser), its `SourceLanguage` constant + `CodeParser.configuration` (primitives/collections, any framework stereotypes or generated-code filter, build-output dirs), its build-system detector(s), then registration in `UMLLibrary` (`AnalysisService.standard`). Do **not** add language data to any agnostic target.
