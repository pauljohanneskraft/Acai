import Foundation
import SwiftUI
import UMLLibrary
import UMLCore
import UMLDiagram
import UMLRender

@MainActor
final class ProjectBrowserViewModel: ObservableObject {
    @Published var store: ProjectStore
    @Published var selection: Selection?

    enum Selection: Hashable {
        case project(UUID)
        case codebase(UUID)
        case generatedDiagram(UUID)
        case freeformDiagram(UUID)
    }

    init(store: ProjectStore = ProjectStore()) {
        self.store = store
    }

    func persistChanges() {
        store.save()
        objectWillChange.send()
    }

    private func persistProject(_ projectID: UUID) {
        if let project = store.projects.first(where: { $0.id == projectID }) {
            store.saveProject(project)
        }
        objectWillChange.send()
    }

    // MARK: - Project CRUD

    func addProject(title: String, subtitle: String) {
        let project = Project(title: title, subtitle: subtitle, codebases: [])
        store.projects.append(project)
        persistChanges()
    }

    func updateProject(id: UUID, title: String, subtitle: String) {
        guard let projectIndex = store.projects.firstIndex(where: { $0.id == id }) else { return }
        store.projects[projectIndex].title = title
        store.projects[projectIndex].subtitle = subtitle
        persistChanges()
    }

    func removeProject(_ projectID: UUID) {
        guard let project = store.projects.first(where: { $0.id == projectID }) else { return }
        // Clean up diagram files
        for did in project.generatedDiagramIDs { store.deleteGeneratedDiagramFile(did) }
        for did in project.freeformDiagramIDs { store.deleteFreeformDiagramFile(did) }
        store.deleteProjectFile(projectID)
        store.projects.removeAll { $0.id == projectID }
        persistChanges()
    }

    // MARK: - Codebase CRUD

    func addCodebase(to projectID: UUID, name: String, directoryURL: URL) {
        guard let projectIndex = store.projects.firstIndex(where: { $0.id == projectID }) else { return }
        let codebase = Codebase(name: name, directoryPath: directoryURL.path)
        store.projects[projectIndex].codebases.append(codebase)
        persistChanges()
    }

    func updateCodebase(id: UUID, name: String) {
        for i in store.projects.indices {
            if let j = store.projects[i].codebases.firstIndex(where: { $0.id == id }) {
                store.projects[i].codebases[j].name = name
                persistChanges()
                return
            }
        }
    }

    func removeCodebase(_ codebaseID: UUID) {
        for i in store.projects.indices {
            store.projects[i].codebases.removeAll { $0.id == codebaseID }
            // Remove generated diagrams linked to this codebase.
            let toRemove = store.projects[i].generatedDiagramIDs.filter { did in
                store.generatedDiagrams[did]?.codebaseID == codebaseID
            }
            for did in toRemove {
                store.projects[i].generatedDiagramIDs.removeAll { $0 == did }
                store.deleteGeneratedDiagramFile(did)
            }
        }
        store.deleteArtifactFile(for: codebaseID)
        persistChanges()
    }

    func reindex(codebaseID: UUID) async {
        guard let pIndex = store.projects.firstIndex(where: { $0.id == projectID(for: codebaseID) }),
              let cIndex = store.projects[pIndex].codebases.firstIndex(where: { $0.id == codebaseID }) else { return }
        let url = URL(fileURLWithPath: store.projects[pIndex].codebases[cIndex].directoryPath).standardizedFileURL

        do {
            let artifact = try await Task.detached(priority: .userInitiated) {
                try AnalysisService.shared.analyzeProject(at: url, allowedLanguages: [])
            }.value
            let enriched = ClassDiagramEnricher.enrich(
                artifact,
                options: EnrichmentOptions(
                    inferCompositionFromProperties: true,
                    inferDependencyFromMethods: true,
                    showExternalTypes: true
                )
            )
            let newArtifact = CodeArtifact(
                metadata: artifact.metadata,
                types: enriched.types,
                relationships: enriched.relationships,
                freestandingFunctions: artifact.freestandingFunctions
            )
            store.projects[pIndex].codebases[cIndex].hasArtifact = true
            store.projects[pIndex].codebases[cIndex].lastIndexed = Date()
            store.saveArtifact(newArtifact, for: codebaseID)
            persistProject(store.projects[pIndex].id)
        } catch {
            print("Reindex failed: \(error)")
        }
    }

    // MARK: - Generated Diagram CRUD

    /// Creates a generated diagram of any kind; `content` carries the type together with its
    /// type-specific configuration.
    func addGeneratedDiagram(
        to projectID: UUID,
        codebaseID: UUID,
        content: GeneratedDiagram.Content
    ) -> UUID? {
        guard let projectIndex = store.projects.firstIndex(where: { $0.id == projectID }) else { return nil }
        var diagram = GeneratedDiagram(name: "", content: content, codebaseID: codebaseID)
        diagram.name = diagram.autoName(codebaseName: codebase(for: codebaseID)?.name ?? "")
        store.projects[projectIndex].generatedDiagramIDs.append(diagram.id)
        store.saveGeneratedDiagram(diagram)
        persistChanges()
        return diagram.id
    }

    /// Updates the entry-point configuration of a sequence diagram and clears its saved
    /// participant positions (the participant set may have changed).
    func updateSequenceConfiguration(
        diagramID: UUID,
        configuration: SequenceDiagramConfiguration
    ) {
        guard var diagram = store.generatedDiagrams[diagramID] else { return }
        diagram.sequenceConfiguration = configuration
        diagram.nodePositions = [:]
        if !diagram.isNameUserDefined {
            diagram.name = diagram.autoName(codebaseName: codebase(for: diagram.codebaseID)?.name ?? "")
        }
        diagram.lastModified = Date()
        store.saveGeneratedDiagram(diagram)
        objectWillChange.send()
    }

    /// Updates the variable configuration of a state diagram and clears its saved
    /// node positions (the state set may have changed).
    func updateStateConfiguration(
        diagramID: UUID,
        configuration: StateDiagramConfiguration
    ) {
        guard var diagram = store.generatedDiagrams[diagramID] else { return }
        diagram.stateConfiguration = configuration
        diagram.nodePositions = [:]
        if !diagram.isNameUserDefined {
            diagram.name = diagram.autoName(codebaseName: codebase(for: diagram.codebaseID)?.name ?? "")
        }
        diagram.lastModified = Date()
        store.saveGeneratedDiagram(diagram)
        objectWillChange.send()
    }

    func updateGeneratedDiagramPositions(
        diagramID: UUID,
        positions: [String: CGPoint],
        sizes: [String: CGSize] = [:],
        scale: CGFloat,
        offset: CGPoint
    ) {
        guard var diagram = store.generatedDiagrams[diagramID] else { return }
        diagram.nodePositions = positions.mapValues { .init(point: $0) }
        if !sizes.isEmpty {
            diagram.nodeSizes = sizes.mapValues { .init(size: $0) }
        }
        diagram.canvasScale = Double(scale)
        diagram.canvasOffsetX = Double(offset.x)
        diagram.canvasOffsetY = Double(offset.y)
        diagram.lastModified = Date()
        store.saveGeneratedDiagram(diagram)
        objectWillChange.send()
    }

    /// Updates the rendering configuration of a class diagram (no-op for other types).
    func updateClassDiagramConfiguration(diagramID: UUID, configuration: ClassDiagramConfiguration) {
        guard var diagram = store.generatedDiagrams[diagramID] else { return }
        diagram.classConfiguration = configuration
        diagram.lastModified = Date()
        store.saveGeneratedDiagram(diagram)
        objectWillChange.send()
    }

    func renameGeneratedDiagram(_ diagramID: UUID, name: String) {
        guard var diagram = store.generatedDiagrams[diagramID] else { return }
        diagram.name = name
        diagram.isNameUserDefined = true
        diagram.lastModified = Date()
        store.saveGeneratedDiagram(diagram)
        objectWillChange.send()
    }

    func removeGeneratedDiagram(_ diagramID: UUID) {
        for i in store.projects.indices {
            store.projects[i].generatedDiagramIDs.removeAll { $0 == diagramID }
        }
        store.deleteGeneratedDiagramFile(diagramID)
        persistChanges()
    }

    func generatedDiagram(for diagramID: UUID) -> GeneratedDiagram? {
        store.generatedDiagrams[diagramID]
    }

    // MARK: - Freeform Diagram CRUD

    func addFreeformDiagram(to projectID: UUID, name: String) -> UUID? {
        guard let projectIndex = store.projects.firstIndex(where: { $0.id == projectID }) else { return nil }
        let diagram = FreeformDiagram(name: name)
        store.projects[projectIndex].freeformDiagramIDs.append(diagram.id)
        store.saveFreeformDiagram(diagram)
        persistChanges()
        return diagram.id
    }

    func updateFreeformDiagram(diagramID: UUID, diagram: FreeformDiagram) {
        var updated = diagram
        updated.lastModified = Date()
        store.saveFreeformDiagram(updated)
        objectWillChange.send()
    }

    func renameFreeformDiagram(_ diagramID: UUID, name: String) {
        guard var diagram = store.freeformDiagrams[diagramID] else { return }
        diagram.name = name
        diagram.lastModified = Date()
        store.saveFreeformDiagram(diagram)
        objectWillChange.send()
    }

    func removeFreeformDiagram(_ diagramID: UUID) {
        for i in store.projects.indices {
            store.projects[i].freeformDiagramIDs.removeAll { $0 == diagramID }
        }
        store.deleteFreeformDiagramFile(diagramID)
        persistChanges()
    }

    func freeformDiagram(for diagramID: UUID) -> FreeformDiagram? {
        store.freeformDiagrams[diagramID]
    }

    // MARK: - Helpers

    func projectID(for codebaseID: UUID) -> UUID? {
        store.projects.first { project in
            project.codebases.contains { $0.id == codebaseID }
        }?.id
    }

    func project(for projectID: UUID) -> Project? {
        store.projects.first(where: { $0.id == projectID })
    }

    func codebase(for codebaseID: UUID) -> Codebase? {
        for p in store.projects {
            if let c = p.codebases.first(where: { $0.id == codebaseID }) {
                return c
            }
        }
        return nil
    }

    func artifact(for codebaseID: UUID) -> CodeArtifact? {
        store.artifact(for: codebaseID)?.resolvingExtensions().filteringGeneratedDartTypes()
    }

    func projectForDiagram(_ diagramID: UUID) -> Project? {
        store.projects.first {
            $0.generatedDiagramIDs.contains(diagramID) ||
            $0.freeformDiagramIDs.contains(diagramID)
        }
    }

    /// All generated diagrams for a project.
    func generatedDiagramsForProject(_ projectID: UUID) -> [GeneratedDiagram] {
        guard let project = store.projects.first(where: { $0.id == projectID }) else { return [] }
        return project.generatedDiagramIDs.compactMap { store.generatedDiagrams[$0] }
    }

    /// All freeform diagrams for a project.
    func freeformDiagramsForProject(_ projectID: UUID) -> [FreeformDiagram] {
        guard let project = store.projects.first(where: { $0.id == projectID }) else { return [] }
        return project.freeformDiagramIDs.compactMap { store.freeformDiagrams[$0] }
    }
}
