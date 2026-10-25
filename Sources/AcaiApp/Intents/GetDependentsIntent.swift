import AppIntents
import Foundation

/// Answers with every type that transitively depends on a type; its static strings live in `AppIntents.xcstrings`.
struct GetDependentsIntent: AppIntent {
    static let title = LocalizedStringResource("Intent.GetDependents.Title", table: "AppIntents")
    static let description = IntentDescription(
        LocalizedStringResource("Intent.GetDependents.Description", table: "AppIntents"))

    static var parameterSummary: some ParameterSummary {
        Summary("Intent.GetDependents.Summary \(\.$type) \(\.$codebase)", table: "AppIntents")
    }

    @Parameter(title: LocalizedStringResource("Intent.GetDependents.Codebase", table: "AppIntents"))
    var codebase: CodebaseEntity

    /// A simple name, a qualified name or a type id, resolved the way `acai dependents` resolves its argument.
    @Parameter(title: LocalizedStringResource("Intent.GetDependents.Type", table: "AppIntents"))
    var type: String

    init() {}

    init(codebase: CodebaseEntity, type: String) {
        self.codebase = codebase
        self.type = type
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[TypeEntity]> {
        .result(value: try await answer(in: .app))
    }

    @MainActor
    func answer(in store: ProjectStore) async throws -> [TypeEntity] {
        try await CodebaseInsights(store: store).dependents(ofType: type, codebaseID: codebase.id)
    }
}
