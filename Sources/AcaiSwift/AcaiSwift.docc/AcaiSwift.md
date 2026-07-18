# ``AcaiSwift``

The Swift language plugin — parses `.swift` source into the [AcaiCore](/documentation/acaicore/) model
using Apple's native SwiftSyntax.

## Overview

`AcaiSwift` is a self-contained language plugin. It owns the ``SwiftCodeParser`` (a stateless
[CodeParser](/documentation/acaicore/codeparser) for the `swift` file extension), the
`SourceLanguage.swift` constant, the language's
[LanguageConfiguration](/documentation/acaicore/languageconfiguration), and the build-system
detectors that find Swift source in a project.

Unlike the other parsers, Swift uses **SwiftSyntax** — Apple's own parser — rather than
Tree-sitter, so it tracks the language exactly. It discovers source through two detectors:
``SwiftPackageManagerDetector`` (SwiftPM `Package.swift` packages) and ``XcodeDetector``
(`.xcodeproj`/`.xcworkspace`).

You can use the parser directly on a single file, or let
[AnalysisService](/documentation/acaicore/analysisservice) pick it for you:

```swift
import AcaiSwift

let artifact = try SwiftCodeParser().parse(source: sourceText, fileName: "Model.swift")
```

## Topics

### Parsing

- ``SwiftCodeParser``

### Project discovery

- ``SwiftPackageManagerDetector``
- ``XcodeDetector``
