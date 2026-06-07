---
name: add-language
description: Add a new source-language parser to the UML tool (new Tree-sitter dependency, library target, test target, SourceLanguage case, CodeParser implementation, and AnalysisService registration). Use when the user wants to support parsing a new programming language.
---

# Add a language parser

Adding language `<Lang>` (e.g. `Rust`) means touching these files in order. Mirror the existing Kotlin parser (`Sources/UMLKotlin/`) as the reference implementation for any Tree-sitter language.

1. **Dependency** — in `Package.swift`, add the Tree-sitter grammar package to `dependencies` (search github.com/tree-sitter for the official grammar; pin `from:` a released version, only use `branch:` if no tags exist, as Dart does).

2. **Library product + target** — add `.library(name: "UML<Lang>", targets: ["UML<Lang>"])` to `products`, and a `.target` named `UML<Lang>` depending on `"UMLCore"`, `"UMLTreeSitter"`, and `.product(name: "TreeSitter<Lang>", package: "...")`.

3. **Test target** — add `.testTarget(name: "UML<Lang>Tests", dependencies: ["UML<Lang>", "UMLCore"])`.

4. **SourceLanguage case** — add `case <lang>` to the `SourceLanguage` enum in `Sources/UMLCore/CodeArtifact.swift`. It's `CaseIterable` and `String`-raw; keep naming consistent (lowerCamel, e.g. `typeScript`).

5. **Parser** — create `Sources/UML<Lang>/<Lang>CodeParser.swift`: a `public struct <Lang>CodeParser: CodeParser` (stateless) exposing `language`, `fileExtensions` (lowercase, no dot), and `parse(source:fileName:) -> CodeArtifact`. Split extraction logic into `*Extractor*.swift` helpers like the Kotlin module does.

6. **Register** — add `<Lang>CodeParser()` to the default `parsers` array in `AnalysisService` (`Sources/UMLLibrary/AnalysisService.swift`), and add `"UML<Lang>"` to the dependency lists of `UMLLibrary`, `UMLCLI`, and `UMLApp` in `Package.swift`.

7. **Tests** — add fixtures under `Tests/UML<Lang>Tests/`, mirroring an existing parser's test layout.

Then run `swift build`, `swift test --filter UML<Lang>Tests`, and `swiftlint lint --strict`.
