import AcaiCore
import AppIntents
import Foundation

/// A declared type, addressed by the artifact's own type id — the same identity the app's links,
/// the CLI and the MCP server use, so a Shortcut can carry one between actions.
///
/// Its static strings live in the app targets' `AppIntents.xcstrings`: App Intents metadata only
/// resolves them from the main bundle.
struct TypeEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Intent.TypeEntity.TypeName", table: "AppIntents"))
    static let defaultQuery = TypeEntityQuery()

    let id: String
    let qualifiedName: String
    /// `file:line`, absent for a type no parser gave an extent for.
    let location: String?

    /// Never localized: a type name and a path are what the parser read, not chrome.
    var displayRepresentation: DisplayRepresentation {
        guard let location else { return DisplayRepresentation(title: "\(qualifiedName)") }
        return DisplayRepresentation(title: "\(qualifiedName)", subtitle: "\(location)")
    }
}

extension TypeEntity {
    init(_ dependent: ImpactAnalysis.Dependent) {
        self.init(
            id: dependent.id,
            qualifiedName: dependent.qualifiedName,
            location: dependent.location?.intentDisplay)
    }

    init(_ type: TypeDeclaration) {
        self.init(id: type.id, qualifiedName: type.qualifiedName, location: type.location?.intentDisplay)
    }
}

extension SourceLocation {
    /// The `file:line` form every Acai surface prints a location as.
    var intentDisplay: String { "\(filePath):\(line)" }
}

struct TypeEntityQuery: EntityQuery {
    /// A type id is unique within an artifact but not across codebases, so a stored id resolves
    /// against every indexed codebase and the first reading of it wins.
    @MainActor
    func entities(for identifiers: [String]) async throws -> [TypeEntity] {
        let browser = ProjectBrowserViewModel(store: .app)
        let wanted = Set(identifiers)
        return browser.store.projects
            .flatMap(\.codebases)
            .compactMap { browser.artifact(for: $0.id) }
            .flatMap { $0.flattened() }
            .filter { wanted.contains($0.id) }
            .map { TypeEntity($0) }
            .removingDuplicates(by: \.id)
    }
}
