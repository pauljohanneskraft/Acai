---
name: add-language
description: Add a new source-language plugin to the UML tool (new Tree-sitter dependency, plugin target + test target, a SourceLanguage constant, a CodeParser with its LanguageConfiguration and build-system detector, and registration in the UMLLibrary composition root). Use when the user wants to support parsing a new programming language.
---

# Add a language plugin

A language is a **self-contained plugin**: its own target owning the parser, its `SourceLanguage`
constant, its `LanguageConfiguration` (the language's quirks), and its build-system detector(s).
The agnostic engine (`UMLCore`, `UMLDiagram`, `UMLLibrary`'s agnostic surface) must never name or
special-case a language — all language/framework data lives in the plugin and reaches the engine by
injection. See `CLAUDE.md` → "The language-agnostic boundary".

Use `Sources/UMLDart/` as the reference: a standalone Tree-sitter plugin with a `SourceLanguage`
constant, a `LanguageConfiguration` (including a `GeneratedCodeFilter`), and a `FlutterDetector`.

Adding language `<Lang>` (e.g. `Rust`) means, in order:

1. **Dependency** — in `Package.swift`, add the Tree-sitter grammar package to `dependencies`
   (search github.com/tree-sitter for the official grammar; pin `from:` a released version, only use
   `branch:` if no tags exist, as Dart does).

2. **Library product + target** — add `.library(name: "UML<Lang>", targets: ["UML<Lang>"])` to
   `products`, and a `.target` named `UML<Lang>` depending on `"UMLCore"`, `"UMLTreeSitter"`, and
   `.product(name: "TreeSitter<Lang>", package: "...")`. (For a JVM-family language, extend the
   existing `UMLJVM` target instead of making a new one.)

3. **Test target** — add `.testTarget(name: "UML<Lang>Tests", dependencies: ["UML<Lang>", "UMLCore"])`.

4. **Parser** — create `Sources/UML<Lang>/<Lang>CodeParser.swift`: a stateless
   `public struct <Lang>CodeParser: CodeParser` exposing `language`, `fileExtensions` (lowercase, no
   dot), `parse(source:fileName:) -> CodeArtifact`, and `configuration`. Split extraction into
   `*Extractor*.swift` helpers like the Dart/JVM modules do.

5. **Language identity + quirks** — create `Sources/UML<Lang>/<Lang>Language.swift` with:
   - `extension CodeArtifact.SourceLanguage { public static let <lang> = .init(rawValue: "<lang>") }`
     — the constant lives in the plugin, never in `UMLCore` (lowerCamel raw value, e.g. `typeScript`).
   - `extension <Lang>CodeParser { public var configuration: LanguageConfiguration { … } }` listing
     this language's `primitiveTypeNames`, `collectionTypeNames`, any framework `annotationStereotypes`,
     an optional `generatedCodeFilter`, and `excludedDirectories` (build-output/dependency dirs).
     `configuration` is required — there is no empty default; state it explicitly.

6. **Build-system detector (optional)** — if the language has a recognisable project layout, add a
   `BuildSystemDetector` in the plugin (e.g. `Sources/UML<Lang>/<Lang>Detector.swift`), mirroring
   `FlutterDetector`. A `public init()` is required (it's constructed from another module).

7. **Register in the composition root** — in `Sources/UMLLibrary/`:
   - add `<Lang>CodeParser()` to `standardParsers` in `AnalysisService+Standard.swift`,
   - add the detector (if any) to `standardDetectors` there,
   - add `@_exported import UML<Lang>` to `Exports.swift`,
   - add `"UML<Lang>"` to `UMLLibrary`'s dependency list in `Package.swift`.
   `UMLCLI`/`UMLApp` need no change — they depend on `UMLLibrary`.

8. **Tests** — add fixtures under `Tests/UML<Lang>Tests/`, mirroring an existing plugin's layout.

Then run `swift build`, `swift test --filter UML<Lang>Tests`, and `swiftlint lint --strict`.
