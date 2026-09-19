import AppIntents
import Foundation

struct CodebaseEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Intent.CodebaseEntity.TypeName", table: "AppIntents"))
    static let defaultQuery = CodebaseEntityQuery()

    let id: UUID
    let name: String
    let projectTitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(projectTitle)")
    }
}

struct CodebaseEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [CodebaseEntity] {
        allEntities.filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [CodebaseEntity] {
        allEntities.filter {
            $0.name.localizedStandardContains(string) || $0.projectTitle.localizedStandardContains(string)
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [CodebaseEntity] {
        allEntities
    }

    @MainActor
    private var allEntities: [CodebaseEntity] {
        ProjectStore.app.projects
            .flatMap { project in
                project.codebases.map { CodebaseEntity(id: $0.id, name: $0.name, projectTitle: project.title) }
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
