import AppIntents
import Foundation

/// Answers with the codebase's numbers instead of opening the app, so a Shortcut can read them and
/// branch — the composition step `ReindexCodebaseIntent` alone can't give it.
///
/// Its static strings live in the app targets' `AppIntents.xcstrings`: App Intents metadata only
/// resolves them from the main bundle.
struct GetCodebaseMetricsIntent: AppIntent {
    static let title = LocalizedStringResource("Intent.GetCodebaseMetrics.Title", table: "AppIntents")
    static let description = IntentDescription(
        LocalizedStringResource("Intent.GetCodebaseMetrics.Description", table: "AppIntents"))

    @Parameter(title: LocalizedStringResource("Intent.GetCodebaseMetrics.Codebase", table: "AppIntents"))
    var codebase: CodebaseEntity

    init() {}

    init(codebase: CodebaseEntity) {
        self.codebase = codebase
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<CodebaseMetricsEntity> {
        let insights = CodebaseInsights(browser: ProjectBrowserViewModel(store: .app))
        return .result(value: try await insights.metrics(codebaseID: codebase.id))
    }
}
