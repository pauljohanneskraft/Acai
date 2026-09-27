import Foundation

// One diagram per file, saved and deleted through `diagramWriter` so a pending debounced write can
// never land after a synchronous save or a deletion. Kept out of `ProjectStore.swift` only to stay
// under that type's own body-length limit.
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

    func saveFreeformDiagram(_ diagram: FreeformDiagram) {
        freeformDiagrams[diagram.id] = diagram
        let url = diagramsDir.appendingPathComponent("freeform_\(diagram.id.uuidString).json")
        do {
            try JSONEncoder().encode(diagram).write(to: url, options: .atomic)
        } catch {
            report(.app("Error.ProjectStore.SaveDiagram \(diagram.name) \(error.localizedDescription)"))
        }
    }

    func deleteGeneratedDiagramFile(_ id: UUID) {
        generatedDiagrams.removeValue(forKey: id)
        diagramWriter.cancel(id)
        try? FileManager.default.removeItem(at: generatedDiagramURL(id))
    }

    func deleteFreeformDiagramFile(_ id: UUID) {
        freeformDiagrams.removeValue(forKey: id)
        let url = diagramsDir.appendingPathComponent("freeform_\(id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }
}
