# ``UMLDiagram``

Turn a parsed [CodeArtifact](/documentation/umlcore/codeartifact) into a diagram — as Graphviz **DOT** or **Mermaid** text.

## Overview

`UMLDiagram` is the agnostic rendering-to-text layer. Hand it a
[CodeArtifact](/documentation/umlcore/codeartifact) and a set of options and it produces a diagram
in a format you can save, diff, or pipe into Graphviz. It knows nothing about any specific
language: it receives a [LanguageConfiguration](/documentation/umlcore/languageconfiguration) via
``ClassDiagramOptions`` rather than special-casing languages itself.

Five diagram families live here, all derived from the same artifact:

- **Class diagrams** — ``ClassDiagramDOTRenderer`` (DOT) and ``ClassDiagramMermaidRenderer`` (Mermaid), tuned
  through ``ClassDiagramOptions`` (members, access filtering, inferred composition, dependency
  edges, external types, ``ClassDiagramOptions/GroupingStrategy``, ``DiagramTheme``,
  ``ClassDiagramOptions/LayoutDirection``).
- **Sequence diagrams** — ``SequenceDiagram`` traced from an entry point via
  ``SequenceDiagramConfiguration``.
- **State diagrams** — ``StateDiagram`` from value-flow analysis via ``StateDiagramConfiguration``
  (failures surface as ``StateDiagramAnalysisError``).
- **Package diagrams** — ``PackageDependencyDiagram`` with module instability/abstractness metrics.
- **Call graphs** — ``CallGraph`` over a chosen ``CallGraphScope``.

For a pixel image instead of text, pair this with [UMLRender](/documentation/umlrender/) on Apple
platforms, or render the DOT with Graphviz (`dot -Tpng`) anywhere.

### Quick example

```swift
let options = ClassDiagramOptions(language: artifact.standardLanguageConfiguration)
let dot = ClassDiagramDOTRenderer(options: options).generate(from: artifact)
```

## Topics

### Class diagrams

- ``ClassDiagramDOTRenderer``
- ``ClassDiagramOptions``
- ``ClassDiagramMermaidRenderer``
- ``ClassDiagram``
- ``EnrichmentOptions``
- ``ClassDiagramOptions/GroupingStrategy``
- ``DiagramTheme``
- ``ClassDiagramOptions/LayoutDirection``

### Other diagram types

- ``SequenceDiagram``
- ``SequenceDiagramConfiguration``
- ``StateDiagram``
- ``StateDiagramConfiguration``
- ``StateDiagramAnalysisError``
- ``PackageDependencyDiagram``
- ``CallGraph``
- ``CallGraphScope``

### Output formats

- ``DiagramFormat``
- ``DiagramExport``
- ``DOTRenderer``
