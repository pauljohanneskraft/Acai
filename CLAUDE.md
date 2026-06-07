# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Swift 6 SwiftPM package that parses source code in five languages and emits UML class diagrams in DOT/Graphviz format. Shipped as a CLI (`UMLCLI` → `uml`) and a macOS 15+ SwiftUI app (`UMLApp`).

## Commands

- Build: `swift build`
- Test: `swift test --parallel`
- Single test: `swift test --filter UMLKotlinTests` (target) or `--filter UMLKotlinTests/SomeTest/testCase`
- Lint: `swiftlint lint --strict`
- Format: `swift format --in-place --recursive --configuration .swift-format Sources Tests` (uses the toolchain `swift format`, not the `swift-format` binary)

Release binaries are **not** plain `swift build` — use the scripts in `Scripts/` (they build `-c release --arch arm64` and assemble the `.app` bundle): `cli_create.sh`, `cli_install.sh`, `app_create.sh`, `app_install.sh` (+ matching `*_uninstall.sh`).

## Before a change is done

1. `swiftlint lint --strict` passes (CI enforces this; opt-in + analyzer rules are on).
2. `swift test --parallel` passes.

Linux must keep building, but that's verified by CI only — no local Linux gate. Be mindful that `UMLApp` is macOS-only (`#if canImport(SwiftUI)` in `Package.swift`) and the app scripts use macOS tools (`sips`, `iconutil`).

## Architecture

Layered, one module per concern (see `Package.swift`):

- `UMLCore` — data models. `CodeArtifact.SourceLanguage` is the language enum; `CodeParser` is the parser protocol (`language`, `fileExtensions`, `parse(source:fileName:)`).
- `UMLTreeSitter` — shared Tree-sitter helpers, re-exports `SwiftTreeSitter`.
- Per-language parsers, each depending on `UMLCore` (+ `UMLTreeSitter` for non-Swift): `UMLSwift` (SwiftSyntax), `UMLKotlin`, `UMLJS` (TS + JS), `UMLJava`, `UMLDart` (all Tree-sitter).
- `UMLDiagram` — DOT/Graphviz generation.
- `UMLLibrary` — coordination. `AnalysisService` holds the `[any CodeParser]` registry and dispatches by language; this is where parsers are wired in.
- `UMLCLI`, `UMLApp` — entry points; both list every parser module as a dependency.

## Style

- 4-space indentation, 120-column lines (`.swift-format`, `.swiftlint.yml`).
- Type nesting capped at 2 levels; cyclomatic complexity warns at 10.
- Parsers are stateless `struct`s conforming to `CodeParser`.

## Adding a language

Use the `/add-language` skill — it covers the dep, target, parser, enum case, and `AnalysisService` registration in order.
