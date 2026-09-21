import AppIntents
import Foundation
import UniformTypeIdentifiers

/// Runs in the app process, sharing the windows' store instead of racing it on disk. Unlike
/// ``OpenDiagramIntent`` this doesn't bring the app forward — it hands Shortcuts a file, the same
/// way exporting from the app itself does, just without the file-picker/share-sheet UI.
struct ExportDiagramIntent: AppIntent {
    static let title = LocalizedStringResource("Intent.ExportDiagram.Title", table: "AppIntents")
    static let description = IntentDescription(
        LocalizedStringResource("Intent.ExportDiagram.Description", table: "AppIntents"))

    @Parameter(title: LocalizedStringResource("Intent.ExportDiagram.Diagram", table: "AppIntents"))
    var diagram: DiagramEntity

    init() {}

    init(diagram: DiagramEntity) {
        self.diagram = diagram
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let browser = ProjectBrowserViewModel(store: .app)
        let (filename, data) = try DiagramExporter(browser: browser).exportPNGData(diagramID: diagram.id)
        let file = IntentFile(data: data, filename: "\(filename).png", type: .png)
        return .result(value: file)
    }
}
