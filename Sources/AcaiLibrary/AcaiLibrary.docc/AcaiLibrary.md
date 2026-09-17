# ``AcaiLibrary``

The composition root — the only module that names the built-in languages.

## Overview

`AcaiLibrary` wires every language plugin into [AnalysisService](/documentation/acaicore/analysisservice)`.standard`:
the nine parsers, their `LanguageConfiguration`s and their build-system detectors. It also
`@_exported import`s [AcaiCore](/documentation/acaicore/), [AcaiDiagram](/documentation/acaidiagram/)
and the plugins, so a single `import AcaiLibrary` surfaces the whole package.

That concentration is deliberate. Every agnostic module below stays free of language names, which is
what lets an outside consumer register a language exactly the way the built-ins do — see
[Adding a Language](/documentation/guides/addingalanguage).

New here? Start with [the package overview](/documentation/guides) for the map of the modules, or
[Getting Started](/documentation/guides/gettingstarted) to analyze a project in a few lines.

## Topics

### Essentials

- [AnalysisService](/documentation/acaicore/analysisservice)
