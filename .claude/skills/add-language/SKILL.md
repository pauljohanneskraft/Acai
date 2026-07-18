---
name: add-language
description: Add a new source-language plugin to the Acai tool (new Tree-sitter dependency, plugin target + test target, a SourceLanguage constant, a CodeParser with its LanguageConfiguration and build-system detector, and registration in the AcaiLibrary composition root). Use when the user wants to support parsing a new programming language.
---

# Add a language plugin

A language is a **self-contained plugin**: its own target owning the parser, its `SourceLanguage`
constant, its `LanguageConfiguration` (the language's quirks), and its build-system detector(s).
The agnostic engine (`AcaiCore`, `AcaiDiagram`, `AcaiLibrary`'s agnostic surface) must never name or
special-case a language — all language/framework data lives in the plugin and reaches the engine by
injection. See `CLAUDE.md` → "The language-agnostic boundary".

Use `Sources/AcaiDart/` as the reference: a standalone Tree-sitter plugin with a `SourceLanguage`
constant, a `LanguageConfiguration` (including a `GeneratedCodeFilter`), and a `FlutterDetector`.

Adding language `<Lang>` (e.g. `Rust`) means, in order:

1. **Dependency** — in `Package.swift`, add the Tree-sitter grammar package to `dependencies`
   (search github.com/tree-sitter for the official grammar; pin `from:` a released version, only use
   `branch:` if no tags exist, as Dart does).

2. **Library product + target** — add `.library(name: "Acai<Lang>", targets: ["Acai<Lang>"])` to
   `products`, and a `.target` named `Acai<Lang>` depending on `"AcaiCore"`, `"AcaiTreeSitter"`, and
   `.product(name: "TreeSitter<Lang>", package: "...")`. (For a JVM-family language, extend the
   existing `AcaiJVM` target instead of making a new one.)

3. **Test target** — add `.testTarget(name: "Acai<Lang>Tests", dependencies: ["Acai<Lang>", "AcaiCore"])`.

4. **Parser** — create `Sources/Acai<Lang>/<Lang>CodeParser.swift`: a stateless
   `public struct <Lang>CodeParser: CodeParser` exposing `language`, `fileExtensions` (lowercase, no
   dot), `parse(source:fileName:) -> CodeArtifact`, and `configuration`. Split extraction into
   `*Extractor*.swift` helpers like the Dart/JVM modules do.

5. **Language identity + quirks** — create `Sources/Acai<Lang>/<Lang>Language.swift` with:
   - `extension CodeArtifact.SourceLanguage { public static let <lang> = .init(rawValue: "<lang>") }`
     — the constant lives in the plugin, never in `AcaiCore` (lowerCamel raw value, e.g. `typeScript`).
   - `extension <Lang>CodeParser { public var configuration: LanguageConfiguration { … } }` listing
     this language's `primitiveTypeNames`, `collectionTypeNames`, any framework `annotationStereotypes`,
     an optional `generatedCodeFilter`, and `excludedDirectories` (build-output/dependency dirs).
     `configuration` is required — there is no empty default; state it explicitly.

6. **Build-system detector (optional)** — if the language has a recognisable project layout, add a
   `BuildSystemDetector` in the plugin (e.g. `Sources/Acai<Lang>/<Lang>Detector.swift`), mirroring
   `FlutterDetector`. A `public init()` is required (it's constructed from another module).

7. **Register in the composition root** — in `Sources/AcaiLibrary/`:
   - add `<Lang>CodeParser()` to `standardParsers` in `AnalysisService+Standard.swift`,
   - add the detector (if any) to `standardDetectors` there,
   - add `@_exported import Acai<Lang>` to `Exports.swift`,
   - add `"Acai<Lang>"` to `AcaiLibrary`'s dependency list in `Package.swift`.
   `AcaiCLI`/`AcaiApp` need no change — they depend on `AcaiLibrary`.

8. **Tests** — add fixtures under `Tests/Acai<Lang>Tests/`, mirroring an existing plugin's layout.

Then run `swift build`, `swift test --filter Acai<Lang>Tests`, and `swiftlint lint --strict`.
