import Foundation
import UMLCore

// MARK: - Models

/// Persisted as its own JSON file: `<projectID>.json`
/// Diagrams are stored separately — one file per diagram.
/// Code analysis results (CodeArtifact) are stored separately — one file per codebase.
struct Project: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var subtitle: String
    var iconSystemName: String
    var codebases: [Codebase] = []
    /// IDs of generated (stored) diagrams that belong to this project. Diagram data is in a separate file.
    var storedDiagramIDs: [UUID] = []
    /// IDs of custom diagrams that belong to this project. Diagram data is in a separate file.
    var customDiagramIDs: [UUID] = []
}

struct Codebase: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var directoryPath: String
    /// Analysis results are stored in a separate file (`artifacts/codebase_<id>.json`).
    /// Use `ProjectStore.artifact(for:)` to load.
    var hasArtifact: Bool = false
    var languages: [LanguageSummary] = []
    var lastIndexed: Date? = nil
}

struct LanguageSummary: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var language: String
    var filesCount: Int
}

