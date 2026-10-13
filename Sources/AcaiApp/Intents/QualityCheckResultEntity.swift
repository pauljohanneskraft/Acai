import AppIntents
import Foundation

/// One run of a codebase's quality check: the fitness-function verdict plus how its findings split
/// by severity, so a Shortcut can notify only on something critical.
///
/// Its static strings live in the app targets' `AppIntents.xcstrings`: App Intents metadata only
/// resolves them from the main bundle.
struct QualityCheckResultEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Intent.QualityCheckResultEntity.TypeName", table: "AppIntents"))
    static let defaultQuery = QualityCheckResultEntityQuery()

    /// The codebase's own id — the result is a reading of it, so re-resolving re-runs the check.
    let id: UUID
    let codebaseName: String
    let isPassing: Bool
    let criticalCount: Int
    let warningCount: Int
    let infoCount: Int
    let checkedRuleCount: Int
    /// `false` when the check ran against the built-in curated budgets because the codebase has no
    /// `quality.yml` configured, or its rules failed to load.
    let usesConfiguredRules: Bool

    var findingCount: Int { criticalCount + warningCount + infoCount }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(codebaseName)",
            subtitle: isPassing
                ? LocalizedStringResource("Intent.QualityCheckResultEntity.Passed", table: "AppIntents")
                : LocalizedStringResource(
                    "Intent.QualityCheckResultEntity.Failed \(findingCount)", table: "AppIntents"))
    }
}

struct QualityCheckResultEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [QualityCheckResultEntity] {
        let insights = CodebaseInsights(browser: ProjectBrowserViewModel(store: .app))
        var entities: [QualityCheckResultEntity] = []
        for identifier in identifiers {
            if let entity = try? await insights.qualityCheck(codebaseID: identifier) {
                entities.append(entity)
            }
        }
        return entities
    }
}
