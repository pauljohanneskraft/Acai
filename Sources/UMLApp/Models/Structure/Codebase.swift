import Foundation

struct Codebase: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var directoryPath: String
    var hasArtifact: Bool = false
    var lastIndexed: Date?
    /// `true` when the most recent index encountered files that could not be fully parsed.
    var hasParseErrors: Bool = false
}
