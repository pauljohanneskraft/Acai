# ``UMLLibrary``

See your codebase. Point UML at a folder of source code and get a UML class diagram back.

## Overview

UML reads your source the way a compiler's front end would — it actually parses it,
it doesn't grep for keywords — and builds **one unified model** of your types and how
they relate. From that model it draws class diagrams: the boxes, the members, and the
inheritance / composition / dependency arrows between them. It works across **Swift,
Kotlin, Java, TypeScript/JavaScript, and Dart**, in a single mixed-language picture,
with nothing to annotate and no build to run first.

If you only read one page, make it <doc:GettingStarted> — one call to ``AnalysisService``
discovers, parses, and merges an entire project for you.

## A map of the modules

The package is split into small, focused modules. You rarely need all of them at once,
so here's the lay of the land — follow a link whenever you want the full API for one.

### Start here

- **[UMLLibrary](/UML/documentation/umllibrary/)** — the front door. ``AnalysisService`` finds the source
  in a project (SPM, Xcode, Gradle, Maven, Node, Flutter…), runs the right parser for
  each file, and merges the results. Re-exports the core model, so importing this is
  usually all you need.

### The core model

- **[UMLCore](/UML/documentation/umlcore/)** — the shared vocabulary everything else speaks: `CodeArtifact`
  (the parsed model), `TypeDeclaration`, `Member`, `Relationship`, and the `CodeParser`
  protocol every language parser conforms to. Start here if you want to understand the
  shape of the data.

### Language parsers

Each one is a stateless `CodeParser` you can use directly, or let ``AnalysisService`` pick
for you. They turn source text into the same [UMLCore](/UML/documentation/umlcore/) model.

- **[UMLSwift](/UML/documentation/umlswift/)** — Swift, via Apple's native SwiftSyntax.
- **[UMLKotlin](/UML/documentation/umlkotlin/)** — Kotlin (`.kt`, `.kts`).
- **[UMLJS](/UML/documentation/umljs/)** — JavaScript and TypeScript (`.js`, `.ts`, `.tsx`, …).
- **[UMLJava](/UML/documentation/umljava/)** — Java.
- **[UMLDart](/UML/documentation/umldart/)** — Dart.
- **[UMLTreeSitter](/UML/documentation/umltreesitter/)** — the shared Tree-sitter helpers the four
  grammar-based parsers above are built on. Reach for this only if you're writing a new
  parser.

### Diagrams & rendering

Turn a [UMLCore](/UML/documentation/umlcore/) model into something you can look at.

- **[UMLDiagram](/UML/documentation/umldiagram/)** — generates Graphviz **DOT** from a model, with options
  for inferred composition, dependency edges, external types, and grouping.
- **[UMLRender](/UML/documentation/umlrender/)** — on Apple platforms, lays out and renders a model
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
