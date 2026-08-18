import Foundation

extension ProjectBrowserViewModel {
    /// Unlike `QuickOpenView.apply(_:entry:)`, always applies the first resolution — a Spotlight
    /// tap has no context menu to pick an alternate from.
    func applyQuickOpenEntryDefault(_ entry: QuickOpenEntry) {
        switch entry.kind {
        case .project:
            selection = .project(entry.projectID)
        case .codebase:
            guard let codebaseID = entry.codebaseID else { return }
            selection = .codebase(codebaseID)
        case .generatedDiagram:
            guard let id = entry.generatedDiagramID else { return }
            selection = .generatedDiagram(id)
        case .freeformDiagram:
            guard let id = entry.freeformDiagramID else { return }
            selection = .freeformDiagram(id)
        case .type, .method, .module:
            applyCodeElementEntry(entry)
        }
    }

    private func applyCodeElementEntry(_ entry: QuickOpenEntry) {
        guard let reference = entry.reference, let codebaseID = entry.codebaseID,
              let artifact = artifact(for: codebaseID)
        else { return }
        let scopedDiagrams = generatedDiagramsForProject(entry.projectID).filter { $0.codebaseID == codebaseID }
        let resolutions = reference.resolutions(in: artifact, existingDiagrams: scopedDiagrams)
        guard let resolution = resolutions.first else { return }
        switch resolution.target {
        case .existing(let diagramID):
            selection = .generatedDiagram(diagramID)
        case .create(let content):
            if let newID = diagrams.add(to: entry.projectID, codebaseID: codebaseID, content: content) {
                selection = .generatedDiagram(newID)
            }
        }
    }
}
