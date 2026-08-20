import AcaiCore

/// The selection/creation logic behind Quick Open, extracted from `QuickOpenView` so it's testable
/// without a SwiftUI hosting environment — same shape as the app's other ViewModels.
@MainActor
struct QuickOpenController {
    let model: ProjectBrowserViewModel

    func apply(_ resolution: CodeElementResolution?, entry: QuickOpenEntry) {
        switch entry.kind {
        case .project:
            model.selection = .project(entry.projectID)
        case .codebase:
            guard let id = entry.codebaseID else { return }
            model.selection = .codebase(id)
        case .generatedDiagram:
            guard let id = entry.generatedDiagramID else { return }
            model.selection = .generatedDiagram(id)
        case .freeformDiagram:
            guard let id = entry.freeformDiagramID else { return }
            model.selection = .freeformDiagram(id)
        case .type, .method, .module:
            applyResolution(resolution, entry: entry)
        }
    }

    private func applyResolution(_ resolution: CodeElementResolution?, entry: QuickOpenEntry) {
        guard let resolution, let codebaseID = entry.codebaseID else { return }
        switch resolution.target {
        case .existing(let diagramID):
            model.selection = .generatedDiagram(diagramID)
        case .create(let content):
            if let newID = model.diagrams.add(to: entry.projectID, codebaseID: codebaseID, content: content) {
                model.selection = .generatedDiagram(newID)
            }
        }
    }

    /// Pure filter — the debounce/cancellation timing stays in `QuickOpenView`, a View-lifecycle
    /// concern, not business logic.
    func filtered(_ entries: [QuickOpenEntry], matching query: String) -> [QuickOpenEntry] {
        guard !query.isEmpty else { return [] }
        return entries.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
}
