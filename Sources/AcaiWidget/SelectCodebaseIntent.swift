import AppIntents
import Foundation

/// Which codebase the widget shows. Its static strings live in the widget extension target's
/// `AppIntents.xcstrings`, not this module's catalog: App Intents metadata resolves them from the
/// main bundle, which for an extension is the extension's own.
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
