import AcaiCore
import Foundation

/// Renders a diagram (named by id, generated or freeform) to PNG for `ExportDiagramIntent` —
/// reusing `ProjectBrowserViewModel.selection(for:)` for lookup (the same resolution a link or
/// Quick Open uses) and `CodebaseAtlasDiagramRenderer` for generated diagrams (the same per-kind
/// view models the app's own "Export Image" action and Codebase Atlas already render through).
@MainActor
struct DiagramExporter {
    let browser: ProjectBrowserViewModel

    enum Failure: LocalizedError, Equatable {
        case codebaseNotIndexed(String)
        case unsupportedDiagramType(String)

        var errorDescription: String? {
            switch self {
            case .codebaseNotIndexed(let name):
                String(localized: .app("Intent.ExportDiagram.CodebaseNotIndexed \(name)"))
            case .unsupportedDiagramType(let typeName):
                String(localized: .app("Intent.ExportDiagram.UnsupportedType \(typeName)"))
            }
        }
    }

    /// Throws `ProjectBrowserViewModel.AddressFailure.diagramNotFound` for an id that resolves to
    /// neither a generated nor a freeform diagram — the same failure a dead `acai://diagram/…` link
    /// reports elsewhere in the app.
    func exportPNGData(diagramID: UUID, scale: CGFloat = 2) throws -> (filename: String, data: Data) {
        switch try browser.selection(for: .diagram(diagramID)) {
        case .generatedDiagram(let id):
            return try exportGeneratedDiagram(id, scale: scale)
        case .freeformDiagram(let id):
            return try exportFreeformDiagram(id, scale: scale)
        default:
            throw ProjectBrowserViewModel.AddressFailure.diagramNotFound
        }
    }

    private func exportGeneratedDiagram(_ id: UUID, scale: CGFloat) throws -> (filename: String, data: Data) {
        guard let diagram = browser.generatedDiagram(for: id) else {
            throw ProjectBrowserViewModel.AddressFailure.diagramNotFound
        }
        guard let codebase = browser.codebase(for: diagram.codebaseID),
              let artifact = browser.store.artifact(for: diagram.codebaseID)
        else {
            throw Failure.codebaseNotIndexed(browser.codebase(for: diagram.codebaseID)?.name ?? diagram.name)
        }
        switch CodebaseAtlasDiagramRenderer(codebase: codebase, artifact: artifact).render(diagram, scale: scale) {
        case .rendered(let data):
            return (diagram.name, data)
        case .unsupported:
            throw Failure.unsupportedDiagramType(diagram.type.displayName)
        case .failed(let error):
            throw error
        }
    }

    private func exportFreeformDiagram(_ id: UUID, scale: CGFloat) throws -> (filename: String, data: Data) {
        guard let diagram = browser.freeformDiagram(for: id) else {
            throw ProjectBrowserViewModel.AddressFailure.diagramNotFound
        }
        let viewModel = FreeformDiagramViewModel()
        viewModel.configure(diagramID: id, browserModel: browser)
        return (diagram.name, try viewModel.exportPNGData(scale: scale))
    }
}
