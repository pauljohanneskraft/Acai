# ``UMLLibrary``

See your codebase. Point UML at a folder of source code and get a UML class diagram back.

## Overview

UML reads your source the way a compiler's front end would — it actually parses it,
it doesn't grep for keywords — and builds **one unified model** of your types and how
they relate. From that model it draws class diagrams: the boxes, the members, and the
inheritance / composition / dependency arrows between them. It works across **Swift,
Kotlin, Java, TypeScript/JavaScript, Dart, and Python**, in a single mixed-language picture,
with nothing to annotate and no build to run first.

If you only read one page, make it <doc:GettingStarted> — one call to ``AnalysisService``
discovers, parses, and merges an entire project for you.

## A map of the modules

The package is split into small, focused modules. You rarely need all of them at once,
so here's the lay of the land — follow a link whenever you want the full API for one.

### Start here

- **[UMLLibrary](/documentation/umllibrary/)** — the front door. ``AnalysisService`` finds the source
  in a project (SPM, Xcode, Gradle, Maven, Node, Flutter…), runs the right parser for
  each file, and merges the results. Re-exports the core model, so importing this is
  usually all you need.

### The core model

- **[UMLCore](/documentation/umlcore/)** — the shared vocabulary everything else speaks: `CodeArtifact`
  (the parsed model), `TypeDeclaration`, `Member`, `Relationship`, and the `CodeParser`
  protocol every language parser conforms to. Start here if you want to understand the
  shape of the data.

### Language parsers

Each one is a stateless `CodeParser` you can use directly, or let ``AnalysisService`` pick
for you. They turn source text into the same [UMLCore](/documentation/umlcore/) model.

- **[UMLSwift](/documentation/umlswift/)** — Swift, via Apple's native SwiftSyntax.
- **[UMLJS](/documentation/umljs/)** — JavaScript and TypeScript (`.js`, `.ts`, `.tsx`, …).
- **[UMLJVM](/documentation/umljvm/)** — Java and Kotlin (`.java`, `.kt`, `.kts`); one module, as they
  share the JVM build systems.
- **[UMLDart](/documentation/umldart/)** — Dart.
- **[UMLTreeSitter](/documentation/umltreesitter/)** — the shared Tree-sitter helpers the
  grammar-based parsers above are built on. Reach for this only if you're writing a new
  parser.

Each plugin is self-contained: it owns its parser, its `SourceLanguage`, its
``LanguageConfiguration`` (the language's quirks), and its build-system detector(s).

### Diagrams & rendering

Turn a [UMLCore](/documentation/umlcore/) model into something you can look at.

- **[UMLDiagram](/documentation/umldiagram/)** — generates Graphviz **DOT** from a model, with options
  for inferred composition, dependency edges, external types, and grouping.
- **[UMLRender](/documentation/umlrender/)** — on Apple platforms, lays out and renders a model
  straight to a **PNG**, no Graphviz required.

## Topics

### Essentials

- <doc:GettingStarted>
- ``AnalysisService``

### Project Discovery

How ``AnalysisService`` finds the source folders inside a project before parsing. You don't
usually touch these directly — they power the automatic discovery.

- ``ProjectDiscovery``
- ``BuildSystemDetector``
- ``SwiftPackageManagerDetector``
- ``JVMBuildSystemDetector``
- ``NodeDetector``
- ``FlutterDetector``
- ``XcodeDetector``
- ``FallbackDetector``
- ``SourceSpec``

### Supporting Types

- ``UMLConstants``
