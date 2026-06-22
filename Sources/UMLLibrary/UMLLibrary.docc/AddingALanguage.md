# Adding a Language

Teach UML a new language by writing a self-contained plugin — no changes to the engine.

## Overview

UML is deliberately **language-agnostic** at its core. The data model
([CodeArtifact](/documentation/umlcore/codeartifact)), the diagram generators, and the renderer
name no specific language; everything language-specific lives in a plugin and reaches the engine
only as data. That means you can add a language entirely from the outside — the built-in languages
are added the exact same way, with no privileged access.

A language plugin is one new module that brings five things together.

### 1. A parser

Conform a stateless `struct` to [CodeParser](/documentation/umlcore/codeparser): declare its
`fileExtensions`, implement `parse(source:fileName:)` to produce a
[CodeArtifact](/documentation/umlcore/codeartifact), and supply its `configuration`. For anything
other than Swift this is a Tree-sitter grammar plus the shared helpers in
[UMLTreeSitter](/documentation/umltreesitter/) (`SourceFileContext`, `TreeSitterExtracting`, and
the call-site / assignment resolvers).

### 2. A `SourceLanguage` constant

Define it as an extension in your plugin — there are **no** built-in language constants in
[UMLCore](/documentation/umlcore/), by design:

```swift
extension CodeArtifact.SourceLanguage {
    public static let ruby = CodeArtifact.SourceLanguage(rawValue: "ruby")
}
```

### 3. A `LanguageConfiguration`

Describe the language's quirks — primitive and collection types, any framework stereotypes, the
generated-code filter, and build-output directories to ignore. The engine resolves this from the
[LanguageRegistry](/documentation/umlcore/languageregistry), keyed on each artifact's language, so
the configuration is **injected**, never hard-coded into an agnostic module.

### 4. Build-system detector(s)

Conform to [BuildSystemDetector](/documentation/umlcore/buildsystemdetector) so
[AnalysisService](/documentation/umlcore/analysisservice) can find your language's source roots
(e.g. a manifest file at the project root).

### 5. Registration in the composition root

Add your parser and detector to `AnalysisService.standard` here in `UMLLibrary` — the **only**
place that names the built-in languages. That keeps the agnostic boundary intact: the engine
stays free of language names, and external consumers register a language the same way.

> The fastest path is the `/add-language` workflow, which scaffolds the module, the test target,
> and the registration. The existing Tree-sitter plugins under `UMLDart`, `UMLPython`, and
> `UMLCFamily` are good templates to read first.

## See Also

- ``UMLLibrary``
- <doc:GettingStarted>
- [CodeParser](/documentation/umlcore/codeparser)
- [LanguageConfiguration](/documentation/umlcore/languageconfiguration)
