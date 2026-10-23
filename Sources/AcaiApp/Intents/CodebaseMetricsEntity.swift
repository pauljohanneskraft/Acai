import AppIntents
import Foundation

/// The codebase-level numbers the statistics pane shows; its static strings live in `AppIntents.xcstrings`.
struct CodebaseMetricsEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Intent.CodebaseMetricsEntity.TypeName", table: "AppIntents"))
    static let defaultQuery = CodebaseMetricsEntityQuery()

    /// The codebase's own id, so re-resolving takes a fresh reading.
    let id: UUID
    let codebaseName: String

    @Property(title: LocalizedStringResource("Intent.CodebaseMetricsEntity.TypeCount", table: "AppIntents"))
    var typeCount: Int

    @Property(title: LocalizedStringResource("Intent.CodebaseMetricsEntity.ModuleCount", table: "AppIntents"))
    var moduleCount: Int

    /// The highest cyclomatic complexity any single method reaches.
    @Property(title: LocalizedStringResource("Intent.CodebaseMetricsEntity.MaxComplexity", table: "AppIntents"))
    var maxComplexity: Int

    /// Dependency cycles between types.
    @Property(title: LocalizedStringResource("Intent.CodebaseMetricsEntity.CycleCount", table: "AppIntents"))
    var cycleCount: Int

    @Property(title: LocalizedStringResource("Intent.CodebaseMetricsEntity.DeadCodeCount", table: "AppIntents"))
    var deadCodeCount: Int

    /// `0...1`: how much of the codebase parsed cleanly.
    @Property(title: LocalizedStringResource("Intent.CodebaseMetricsEntity.HealthScore", table: "AppIntents"))
    var healthScore: Double

    init(
        id: UUID, codebaseName: String, typeCount: Int, moduleCount: Int, maxComplexity: Int, cycleCount: Int,
        deadCodeCount: Int, healthScore: Double
    ) {
        self.id = id
        self.codebaseName = codebaseName
        self.typeCount = typeCount
        self.moduleCount = moduleCount
        self.maxComplexity = maxComplexity
        self.cycleCount = cycleCount
        self.deadCodeCount = deadCodeCount
        self.healthScore = healthScore
    }

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
        let insights = CodebaseInsights(store: .app)
        var entities: [CodebaseMetricsEntity] = []
        for identifier in identifiers {
            try Task.checkCancellation()
            // A codebase deleted or unindexed since the Shortcut stored it resolves to nothing.
            if let entity = try? await insights.metrics(codebaseID: identifier) {
                entities.append(entity)
            }
        }
        return entities
    }
}
