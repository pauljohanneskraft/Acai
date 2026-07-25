// Batteries-included composition root: re-exports the agnostic engine, diagram generator, and
// every built-in language module so their `SourceLanguage` constants and parsers are visible
// through a single `import AcaiLibrary`.
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
