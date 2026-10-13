import AppIntents
import Foundation

/// Runs the codebase's quality check and answers with its verdict, so "run the check and notify me
/// if anything is critical" is a Shortcut rather than a trip through the app.
///
/// Its static strings live in the app targets' `AppIntents.xcstrings`: App Intents metadata only
/// resolves them from the main bundle.
struct RunQualityCheckIntent: AppIntent {
    static let title = LocalizedStringResource("Intent.RunQualityCheck.Title", table: "AppIntents")
    static let description = IntentDescription(
        LocalizedStringResource("Intent.RunQualityCheck.Description", table: "AppIntents"))

    @Parameter(title: LocalizedStringResource("Intent.RunQualityCheck.Codebase", table: "AppIntents"))
    var codebase: CodebaseEntity

    init() {}

    init(codebase: CodebaseEntity) {
        self.codebase = codebase
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<QualityCheckResultEntity> {
        let insights = CodebaseInsights(browser: ProjectBrowserViewModel(store: .app))
        return .result(value: try await insights.qualityCheck(codebaseID: codebase.id))
    }
}
