import Foundation

// Generated-diagram persistence, routed through `diagramWriter` so a burst of saves coalesces. Kept
// out of `ProjectStore.swift` only to stay under that type's own body-length limit.
extension ProjectStore {

    func generatedDiagramURL(_ diagramID: UUID) -> URL {
        diagramsDir.appendingPathComponent("generated_\(diagramID.uuidString).json")
    }

    func saveGeneratedDiagram(_ diagram: GeneratedDiagram) {
        generatedDiagrams[diagram.id] = diagram
        do {
            try diagramWriter.writeNow(diagram, to: generatedDiagramURL(diagram.id))
        } catch {
            report(.app("Error.ProjectStore.SaveDiagram \(diagram.name) \(error.localizedDescription)"))
        }
    }

    /// The same save for changes a user produces in a burst — stepping through search matches
    /// recentres the canvas on every match. The in-memory diagram updates at once; the encode and
    /// the file write happen off the main actor once the burst stops.
    func saveGeneratedDiagramDebounced(_ diagram: GeneratedDiagram) {
        generatedDiagrams[diagram.id] = diagram
        let name = diagram.name
        diagramWriter.schedule(
            diagram.id, to: generatedDiagramURL(diagram.id),
            latest: { [weak self] in self?.generatedDiagrams[diagram.id] },
            onFailure: { [weak self] error in
                self?.report(.app("Error.ProjectStore.SaveDiagram \(name) \(error.localizedDescription)"))
            }
        )
    }

}
