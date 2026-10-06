import AppIntents
import Foundation
import AcaiAppModel

/// Read from the shared snapshots, since the picker opens while the app isn't running.
struct CodebaseWidgetEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Intent.CodebaseWidgetEntity.TypeName", table: "AppIntents"))
    static let defaultQuery = CodebaseWidgetEntityQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct CodebaseWidgetEntityQuery: EntityStringQuery {
    var snapshots: @Sendable () -> [CodebaseWidgetSnapshot] = {
        CodebaseWidgetSnapshotStore(container: .standard)?.load().snapshots ?? []
    }

    func entities(for identifiers: [UUID]) async throws -> [CodebaseWidgetEntity] {
        allEntities.filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [CodebaseWidgetEntity] {
        allEntities.filter { $0.name.localizedStandardContains(string) }
    }

    func suggestedEntities() async throws -> [CodebaseWidgetEntity] {
        allEntities
    }

    private var allEntities: [CodebaseWidgetEntity] {
        snapshots()
            .map { CodebaseWidgetEntity(id: $0.codebaseID, name: $0.codebaseName) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
