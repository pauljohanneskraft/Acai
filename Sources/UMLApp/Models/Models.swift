import Foundation
import UMLCore

// MARK: - Models

struct Project: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var subtitle: String
    var iconSystemName: String
    var codebases: [Codebase] = []
}

struct Codebase: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var directoryPath: String
    var artifact: CodeArtifact? = nil
    var languages: [LanguageSummary] = [] // kept for backward compatibility, but no longer populated
    var lastIndexed: Date? = nil
}

struct LanguageSummary: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var language: String
    var filesCount: Int
}

