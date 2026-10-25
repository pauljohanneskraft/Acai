import AppIntents
import Foundation

/// A quality check's verdict and findings by severity; its static strings live in `AppIntents.xcstrings`.
struct QualityCheckResultEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Intent.QualityCheckResultEntity.TypeName", table: "AppIntents"))
    static let defaultQuery = QualityCheckResultEntityQuery()

    /// The codebase's own id, so re-resolving re-runs the check.
    let id: UUID
    let codebaseName: String

    /// The quality rules' verdict alone; dead code and parse diagnostics are counted but never fail it.
    @Property(title: LocalizedStringResource("Intent.QualityCheckResultEntity.IsPassing", table: "AppIntents"))
    var isPassing: Bool

    @Property(title: LocalizedStringResource("Intent.QualityCheckResultEntity.CriticalCount", table: "AppIntents"))
    var criticalCount: Int

    @Property(title: LocalizedStringResource("Intent.QualityCheckResultEntity.WarningCount", table: "AppIntents"))
    var warningCount: Int

    @Property(title: LocalizedStringResource("Intent.QualityCheckResultEntity.InfoCount", table: "AppIntents"))
    var infoCount: Int

    @Property(
        title: LocalizedStringResource("Intent.QualityCheckResultEntity.CheckedRuleCount", table: "AppIntents"))
    var checkedRuleCount: Int

    /// `false` when the built-in budgets ran because no `quality.yml` is configured or it failed to load.
    @Property(
        title: LocalizedStringResource("Intent.QualityCheckResultEntity.UsesConfiguredRules", table: "AppIntents"))
    var usesConfiguredRules: Bool

    init(
        id: UUID, codebaseName: String, isPassing: Bool, criticalCount: Int, warningCount: Int, infoCount: Int,
        checkedRuleCount: Int, usesConfiguredRules: Bool
    ) {
        self.id = id
        self.codebaseName = codebaseName
        self.isPassing = isPassing
        self.criticalCount = criticalCount
        self.warningCount = warningCount
        self.infoCount = infoCount
        self.checkedRuleCount = checkedRuleCount
        self.usesConfiguredRules = usesConfiguredRules
    }

    var findingCount: Int { criticalCount + warningCount + infoCount }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(codebaseName)",
            subtitle: isPassing
                ? LocalizedStringResource(
                    "Intent.QualityCheckResultEntity.Passed \(findingCount)", table: "AppIntents")
                : LocalizedStringResource(
                    "Intent.QualityCheckResultEntity.Failed \(findingCount)", table: "AppIntents"))
    }
}

struct QualityCheckResultEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [QualityCheckResultEntity] {
        let insights = CodebaseInsights(store: .app)
        var entities: [QualityCheckResultEntity] = []
        for identifier in identifiers {
            try Task.checkCancellation()
            if let entity = try? await insights.qualityCheck(codebaseID: identifier) {
                entities.append(entity)
            }
        }
        return entities
    }
}
