# Adding a Language

Teach Açaí a new language by writing a self-contained plugin — no changes to the engine.

## Overview

Açaí is deliberately **language-agnostic** at its core. The data model
([CodeArtifact](/documentation/acaicore/codeartifact)), the diagram generators, and the renderer
name no specific language; everything language-specific lives in a plugin and reaches the engine
only as data. That means you can add a language entirely from the outside — the built-in languages
are added the exact same way, with no privileged access.

A language plugin is one new module that brings five things together.

### 1. A parser

Conform a stateless `struct` to [CodeParser](/documentation/acaicore/codeparser): declare its
`fileExtensions`, implement `parse(source:fileName:)` to produce a
[CodeArtifact](/documentation/acaicore/codeartifact), and supply its `configuration`.

For anything other than Swift this is a Tree-sitter grammar plus the shared extraction layer in
[AcaiTreeSitter](/documentation/acaitreesitter/). That layer is split so you write as little as
possible: the recursive walks, the call-receiver decision tree, literal classification and the
declared-type pre-pass are shared values you construct once and keep, and what your plugin supplies
is a pair of narrow adapters — `CallSiteSyntax` and `AssignmentSyntax` — that answer questions about
a *single node*. Declaration bookkeeping and naming live one level up, in
[DeclarationBuilder](/documentation/acaicore/declarationbuilder), which your extractor **owns rather
than conforms to**.

`AcaiPython` is the worked example to copy; every other plugin follows the same shape.

### 2. A `SourceLanguage` constant

Define it as an extension in your plugin — there are **no** built-in language constants in
[AcaiCore](/documentation/acaicore/), by design:

```swift
extension CodeArtifact.SourceLanguage {
    public static let ruby = CodeArtifact.SourceLanguage(rawValue: "ruby")
}
```

### 3. A `LanguageConfiguration`

Describe the language's quirks — primitive and collection types, any framework stereotypes, the
generated-code filter, and build-output directories to ignore. The engine resolves this from the
[LanguageRegistry](/documentation/acaicore/languageregistry), keyed on each artifact's language, so
the configuration is **injected**, never hard-coded into an agnostic module.

### 4. Build-system detector(s)

Conform to [BuildSystemDetector](/documentation/acaicore/buildsystemdetector) so
[AnalysisService](/documentation/acaicore/analysisservice) can find your language's source roots
(e.g. a manifest file at the project root).

### 5. Registration in the composition root

Add your parser and detector to `AnalysisService.standard` here in `AcaiLibrary` — the **only**
place that names the built-in languages. That keeps the agnostic boundary intact: the engine
stays free of language names, and external consumers register a language the same way.

### 6. A place in the shared test suites

Register your parser in `ParserConformanceTests` — which holds every language to the producer
contract documented on [CodeParser](/documentation/acaicore/codeparser) — and add one fixture to the
parser golden suite, which pins a parser's whole encoded artifact so a later refactor of the shared
layer has to reproduce your output exactly. Both are a few lines, and both then guard your plugin
without you maintaining them.

> The fastest path is the `/add-language` workflow, which scaffolds the module, the test target,
> and the registration. Read `Sources/AcaiPython/` first — it is the plugin shaped the way a new one
> should be.

## See Also

- [AcaiLibrary](/documentation/acailibrary/)
- <doc:GettingStarted>
- [CodeParser](/documentation/acaicore/codeparser)
- [LanguageConfiguration](/documentation/acaicore/languageconfiguration)
