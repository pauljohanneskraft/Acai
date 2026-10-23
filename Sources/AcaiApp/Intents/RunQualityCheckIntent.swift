import AppIntents
import Foundation

/// Runs a codebase's quality check and answers with its verdict; its static strings live in `AppIntents.xcstrings`.
struct RunQualityCheckIntent: AppIntent {
    static let title = LocalizedStringResource("Intent.RunQualityCheck.Title", table: "AppIntents")
    static let description = IntentDescription(
        LocalizedStringResource("Intent.RunQualityCheck.Description", table: "AppIntents"))

    static var parameterSummary: some ParameterSummary {
        Summary("Intent.RunQualityCheck.Summary \(\.$codebase)", table: "AppIntents")
    }

    @Parameter(title: LocalizedStringResource("Intent.RunQualityCheck.Codebase", table: "AppIntents"))
    var codebase: CodebaseEntity

    init() {}

    init(codebase: CodebaseEntity) {
        self.codebase = codebase
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<QualityCheckResultEntity> {
        .result(value: try await answer(in: .app))
    }

    @MainActor
    func answer(in store: ProjectStore) async throws -> QualityCheckResultEntity {
        try await CodebaseInsights(store: store).qualityCheck(codebaseID: codebase.id)
    }
}
