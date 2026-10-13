import AppIntents
import Foundation

/// Its strings live in the extension target's `AppIntents.xcstrings`: App Intents resolves them from the main bundle.
struct SelectCodebaseIntent: WidgetConfigurationIntent {
    static let title = LocalizedStringResource("Intent.SelectCodebase.Title", table: "AppIntents")
    static let description = IntentDescription(
        LocalizedStringResource("Intent.SelectCodebase.Description", table: "AppIntents"))

    @Parameter(title: LocalizedStringResource("Intent.SelectCodebase.Codebase", table: "AppIntents"))
    var codebase: CodebaseWidgetEntity?

    init() {}

    init(codebase: CodebaseWidgetEntity?) {
        self.codebase = codebase
    }
}
