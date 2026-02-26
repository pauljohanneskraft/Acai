import ArgumentParser
import UMLCore

enum LanguageOption: String, ExpressibleByArgument, CaseIterable {
    case swift
    case kotlin
    case java
    case typescript
    case javascript
    case dart

    var sourceLanguage: CodeArtifact.SourceLanguage {
        switch self {
        case .swift:      return .swift
        case .kotlin:     return .kotlin
        case .java:       return .java
        case .typescript: return .typeScript
        case .javascript: return .javaScript
        case .dart:       return .dart
        }
    }
}
