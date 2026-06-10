# Getting Started

Analyze a codebase and produce a diagram in a few lines.

## Overview

``AnalysisService`` is the front door. Hand it a folder and the languages you care about;
it auto-discovers the source directories (SPM, Xcode, Gradle, Maven, Node, Flutter…),
runs the right parser for each file in parallel, and merges everything into a single
`CodeArtifact`. From there, [UMLDiagram](/documentation/umldiagram/) renders Graphviz DOT.

### Analyze a project

```swift
import UMLLibrary
import UMLDiagram

let project = URL(filePath: "/path/to/your/project")

// Discover, parse, and merge every Swift and Kotlin file under `project`.
let artifact = try AnalysisService.shared.analyzeProject(
    at: project,
    allowedLanguages: [.swift, .kotlin]
)

print("Found \(artifact.types.count) types and \(artifact.relationships.count) relationships.")
```

Pass an empty `allowedLanguages` array to let UML analyze every language it recognizes.

### Render a class diagram

```swift
let dot = DOTGenerator().generate(from: artifact)
try dot.write(to: URL(filePath: "project.dot"), atomically: true, encoding: .utf8)
// Render anywhere Graphviz runs:  dot -Tpng project.dot -o project.png
```

Tune what shows up — inferred composition, dependency arrows, external types, grouping —
through `ClassDiagramOptions` when you create the `DOTGenerator`.

### Render a PNG (Apple platforms)

On macOS you can skip Graphviz entirely and render straight to an image with
[UMLRender](/documentation/umlrender/)'s `DiagramImageRenderer`.

### Parse a single file

Each parser conforms to `CodeParser` and works on its own, no project discovery required:

```swift
import UMLSwift

let artifact = try SwiftCodeParser().parse(source: sourceText, fileName: "Model.swift")
```
