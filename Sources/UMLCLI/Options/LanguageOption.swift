import ArgumentParser
import UMLCore

enum LanguageOption: String, ExpressibleByArgument, CaseIterable {
    case swift
    case kotlin
    case java
    case typescript
    case javascript
    case dart
    case python
    case c
    case cpp

    var sourceLanguage: CodeArtifact.SourceLanguage {
        switch self {
        case .swift:
            return .swift
        case .kotlin:
            return .kotlin
        case .java:
            return .java
        case .typescript:
            return .typeScript
        case .javascript:
            return .javaScript
        case .dart:
            return .dart
        case .python:
            return .python
        case .c:
            return .c
        case .cpp:
            return .cpp
        }
    }
}
