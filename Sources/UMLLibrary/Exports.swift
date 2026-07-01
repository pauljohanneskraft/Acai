// UMLLibrary is the batteries-included composition root. It re-exports the agnostic engine
// (`UMLCore`) and the diagram generator (`UMLDiagram`), plus every built-in language module so
// their `SourceLanguage` constants (`.swift`, `.dart`, …) and parsers are visible to consumers
// (`UMLCLI`, `UMLApp`) through a single `import UMLLibrary`.
@_exported import UMLCore
@_exported import UMLDiagram
@_exported import UMLDiff
@_exported import UMLConformance
@_exported import UMLSwift
@_exported import UMLJS
@_exported import UMLJVM
@_exported import UMLDart
@_exported import UMLPython
@_exported import UMLCFamily
@_exported import UMLCSharp
