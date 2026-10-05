import AppIntents
import Foundation
import AcaiAppModel

/// A codebase the widget can be pointed at. Built from the snapshot file rather than the app's
/// store: the configuration has to offer a choice while the app isn't running.
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
    /// Injected in tests; the real query reads the App Group container.
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
