import AppIntents
import Foundation

/// Answers with a type's blast radius — every type that transitively depends on it — as a list a
/// Shortcut can count or repeat over. Dependents is the app's own word for this.
///
/// Its static strings live in the app targets' `AppIntents.xcstrings`: App Intents metadata only
/// resolves them from the main bundle.
struct GetDependentsIntent: AppIntent {
    static let title = LocalizedStringResource("Intent.GetDependents.Title", table: "AppIntents")
    static let description = IntentDescription(
        LocalizedStringResource("Intent.GetDependents.Description", table: "AppIntents"))

    @Parameter(title: LocalizedStringResource("Intent.GetDependents.Codebase", table: "AppIntents"))
    var codebase: CodebaseEntity

    /// A simple name, a qualified name or a type id — whatever the Shortcut has to hand, resolved
    /// the same way `acai dependents` resolves its argument.
    @Parameter(title: LocalizedStringResource("Intent.GetDependents.Type", table: "AppIntents"))
    var type: String

    init() {}

    init(codebase: CodebaseEntity, type: String) {
        self.codebase = codebase
        self.type = type
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[TypeEntity]> {
        let insights = CodebaseInsights(browser: ProjectBrowserViewModel(store: .app))
        return .result(value: try await insights.dependents(ofType: type, codebaseID: codebase.id))
    }
}
