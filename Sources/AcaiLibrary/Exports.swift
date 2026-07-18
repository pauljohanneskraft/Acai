// AcaiLibrary is the batteries-included composition root. It re-exports the agnostic engine
// (`AcaiCore`) and the diagram generator (`AcaiDiagram`), plus every built-in language module so
// their `SourceLanguage` constants (`.swift`, `.dart`, …) and parsers are visible to consumers
// (`AcaiCLI`, `AcaiApp`) through a single `import AcaiLibrary`.
@_exported import AcaiCore
@_exported import AcaiDiagram
@_exported import AcaiDiff
@_exported import AcaiQuality
@_exported import AcaiSwift
@_exported import AcaiJS
@_exported import AcaiJVM
@_exported import AcaiDart
@_exported import AcaiPython
@_exported import AcaiCFamily
