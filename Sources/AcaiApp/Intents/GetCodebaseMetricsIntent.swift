import AppIntents
import Foundation

/// Answers with a codebase's numbers without opening the app; its static strings live in `AppIntents.xcstrings`.
struct GetCodebaseMetricsIntent: AppIntent {
    static let title = LocalizedStringResource("Intent.GetCodebaseMetrics.Title", table: "AppIntents")
    static let description = IntentDescription(
        LocalizedStringResource("Intent.GetCodebaseMetrics.Description", table: "AppIntents"))

    static var parameterSummary: some ParameterSummary {
        Summary("Intent.GetCodebaseMetrics.Summary \(\.$codebase)", table: "AppIntents")
    }

    @Parameter(title: LocalizedStringResource("Intent.GetCodebaseMetrics.Codebase", table: "AppIntents"))
    var codebase: CodebaseEntity

    init() {}

    init(codebase: CodebaseEntity) {
        self.codebase = codebase
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<CodebaseMetricsEntity> {
        .result(value: try await answer(in: .app))
    }

    @MainActor
    func answer(in store: ProjectStore) async throws -> CodebaseMetricsEntity {
        try await CodebaseInsights(store: store).metrics(codebaseID: codebase.id)
    }
}
