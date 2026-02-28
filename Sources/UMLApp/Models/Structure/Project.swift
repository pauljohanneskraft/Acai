import Foundation

struct Project: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var subtitle: String
    var iconSystemName: String
    var codebases: [Codebase] = []
    var generatedDiagramIDs: [UUID] = []
    var customDiagramIDs: [UUID] = []
}
