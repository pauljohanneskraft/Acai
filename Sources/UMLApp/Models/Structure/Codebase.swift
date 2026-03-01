import Foundation

struct Codebase: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var directoryPath: String
    var hasArtifact: Bool = false
    var lastIndexed: Date?
}
