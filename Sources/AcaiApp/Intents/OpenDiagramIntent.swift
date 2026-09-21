import AppIntents
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Runs in the app process, so opening a diagram this way goes through exactly the same
/// `acai://diagram/<uuid>` address and `ProjectBrowserViewModel.selection(for:)` resolution as a
/// link the app's own Quick Open / Copy Link already produce — no separate lookup that could
/// disagree with it, and a deleted or renamed diagram fails clearly instead of landing nowhere.
struct OpenDiagramIntent: AppIntent {
    static let title = LocalizedStringResource("Intent.OpenDiagram.Title", table: "AppIntents")
    static let description = IntentDescription(
        LocalizedStringResource("Intent.OpenDiagram.Description", table: "AppIntents"))
    static let openAppWhenRun = true

    @Parameter(title: LocalizedStringResource("Intent.OpenDiagram.Diagram", table: "AppIntents"))
    var diagram: DiagramEntity

    init() {}

    init(diagram: DiagramEntity) {
        self.diagram = diagram
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<DiagramEntity> {
        let browser = ProjectBrowserViewModel(store: .app)
        // Thrown as `ProjectBrowserViewModel.AddressFailure`, the same error a bad `acai://` link
        // reports elsewhere in the app.
        _ = try browser.selection(for: .diagram(diagram.id))

        let url = AppAddress.diagram(diagram.id).url
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        await UIApplication.shared.open(url)
        #endif
        return .result(value: diagram)
    }
}
