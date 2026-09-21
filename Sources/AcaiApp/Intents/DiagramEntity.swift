import AppIntents
import Foundation

struct DiagramEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Intent.DiagramEntity.TypeName", table: "AppIntents"))
    static let defaultQuery = DiagramEntityQuery()

    let id: UUID
    let name: String
    /// The codebase (for a generated diagram) or project (for a freeform diagram) it belongs to.
    let containerTitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(containerTitle)")
    }
}

struct DiagramEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [DiagramEntity] {
        allEntities.filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [DiagramEntity] {
        allEntities.filter {
            $0.name.localizedStandardContains(string) || $0.containerTitle.localizedStandardContains(string)
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [DiagramEntity] {
        allEntities
    }

    @MainActor
    private var allEntities: [DiagramEntity] {
        let store = ProjectStore.app
        let codebaseNames = Dictionary(
            uniqueKeysWithValues: store.projects.flatMap(\.codebases).map { ($0.id, $0.name) })
        let generated = store.generatedDiagrams.values.map { diagram in
            DiagramEntity(id: diagram.id, name: diagram.name, containerTitle: codebaseNames[diagram.codebaseID] ?? "")
        }
        let freeform = store.projects.flatMap { project in
            project.freeformDiagramIDs
                .compactMap { store.freeformDiagrams[$0] }
                .map { DiagramEntity(id: $0.id, name: $0.name, containerTitle: project.title) }
        }
        return (generated + freeform).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
