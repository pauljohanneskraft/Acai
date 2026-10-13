import AppIntents
import Foundation

/// The codebase-level numbers the statistics pane shows, as one value a Shortcut can branch on.
///
/// Its static strings live in the app targets' `AppIntents.xcstrings`: App Intents metadata only
/// resolves them from the main bundle.
struct CodebaseMetricsEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Intent.CodebaseMetricsEntity.TypeName", table: "AppIntents"))
    static let defaultQuery = CodebaseMetricsEntityQuery()

    /// The codebase's own id — the metrics are a reading of it, so re-resolving takes a fresh one.
    let id: UUID
    let codebaseName: String
    let typeCount: Int
    let moduleCount: Int
    /// The highest cyclomatic complexity any single method in the codebase reaches.
    let maxComplexity: Int
    /// Dependency cycles between types.
    let cycleCount: Int
    let deadCodeCount: Int
    /// `0...1`: how much of the codebase parsed cleanly, below which every other number here is
    /// correspondingly less trustworthy.
    let healthScore: Double

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(codebaseName)",
            subtitle: LocalizedStringResource(
                "Intent.CodebaseMetricsEntity.Subtitle \(typeCount) \(moduleCount)", table: "AppIntents"))
    }
}

struct CodebaseMetricsEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [CodebaseMetricsEntity] {
        let insights = CodebaseInsights(browser: ProjectBrowserViewModel(store: .app))
        var entities: [CodebaseMetricsEntity] = []
        for identifier in identifiers {
            // A codebase deleted or unindexed since the Shortcut stored it resolves to nothing,
            // which is what an entity query reports by omitting it.
            if let entity = try? await insights.metrics(codebaseID: identifier) {
                entities.append(entity)
            }
        }
        return entities
    }
}
