import AppIntents
import Foundation

/// Runs in the app process, so the run shows in the activity list like a manual one and shares the
/// windows' store instead of racing it on disk.
///
/// Its static strings live in the app targets' `AppIntents.xcstrings`: App Intents metadata only
/// resolves them from the main bundle.
struct ReindexCodebaseIntent: AppIntent {
    static let title = LocalizedStringResource("Intent.ReindexCodebase.Title", table: "AppIntents")
    static let description = IntentDescription(
        LocalizedStringResource("Intent.ReindexCodebase.Description", table: "AppIntents"))
    static let openAppWhenRun = true

    @Parameter(title: LocalizedStringResource("Intent.ReindexCodebase.Codebase", table: "AppIntents"))
    var codebase: CodebaseEntity

    init() {}

    init(codebase: CodebaseEntity) {
        self.codebase = codebase
    }

    enum Failure: LocalizedError {
        case cancelled(String)

        var errorDescription: String? {
            switch self {
            case .cancelled(let name):
                String(localized: .app("Intent.ReindexCodebase.Cancelled \(name)"))
            }
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<CodebaseEntity> & ProvidesDialog {
        let store = ProjectStore.app
        let editor = ProjectCodebaseEditor(
            store: store,
            persist: { store.save() },
            notify: {},
            invalidateAnalysis: { store.analysisInvalidations.send($0) }
        )
        switch try await editor.reindexOutcome(codebaseID: codebase.id) {
        case .completed:
            let dialog = IntentDialog(.app("Intent.ReindexCodebase.Done \(codebase.name)"))
            return .result(value: codebase, dialog: dialog)
        case .cancelled:
            throw Failure.cancelled(codebase.name)
        }
    }
}

/// Lets the app targets pull this package's intents into their App Intents metadata.
public struct AcaiAppIntentsPackage: AppIntentsPackage {}
