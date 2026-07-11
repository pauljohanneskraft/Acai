import CoreGraphics
import Foundation
import UMLCore
import UMLDiagram
import UMLLibrary
import UMLRender

// Diagram-management collaborators carved out of `ProjectBrowserViewModel` (it had grown into a
// god-object). Each is a thin value over the shared `ProjectStore` reference plus the owning view
// model's change hooks, so behaviour is identical: `persist` = save + `objectWillChange`, `notify`
// = `objectWillChange` only. The view model exposes them as `diagrams` / `freeforms`; views call
// e.g. `model.diagrams.rename(...)`.

/// Create/update/delete operations for generated diagrams.
@MainActor
struct GeneratedDiagramEditor {
    let store: ProjectStore
    /// Saves the project list and notifies (used when the diagram set changes).
    let persist: () -> Void
    /// Notifies observers without re-saving the project list (used for in-place diagram edits, which
    /// persist via `store.saveGeneratedDiagram`).
    let notify: () -> Void

    /// Creates a generated diagram of any kind; `content` carries the type and its configuration.
    func add(to projectID: UUID, codebaseID: UUID, content: GeneratedDiagram.Content) -> UUID? {
        guard let projectIndex = store.projects.firstIndex(where: { $0.id == projectID }) else { return nil }
        var diagram = GeneratedDiagram(name: "", content: content, codebaseID: codebaseID)
        diagram.name = diagram.autoName(codebaseName: codebaseName(codebaseID))
        store.projects[projectIndex].generatedDiagramIDs.append(diagram.id)
        store.saveGeneratedDiagram(diagram)
        persist()
        return diagram.id
    }

    /// Updates the entry-point configuration of a sequence diagram, clearing saved positions (the
    /// participant set may have changed).
    func updateSequenceConfiguration(diagramID: UUID, configuration: SequenceDiagramConfiguration) {
        mutate(diagramID, clearPositions: true) { $0.sequenceConfiguration = configuration }
    }

    /// Updates the scope of a call graph, clearing saved positions (the method set changes with scope).
    func updateCallGraphScope(diagramID: UUID, scope: CallGraphScope) {
        mutate(diagramID, clearPositions: true) { $0.callGraphScope = scope }
    }

    /// Updates the variable configuration of a state diagram, clearing saved positions.
    func updateStateConfiguration(diagramID: UUID, configuration: StateDiagramConfiguration) {
        mutate(diagramID, clearPositions: true) { $0.stateConfiguration = configuration }
    }

    /// Updates the rendering configuration of a class diagram (positions kept — a render-option change
    /// never alters the type set).
    func updateClassDiagramConfiguration(diagramID: UUID, configuration: ClassDiagramConfiguration) {
        mutate(diagramID, clearPositions: false) { $0.classConfiguration = configuration }
    }

    func updatePositions(
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
        notify()
    }

    func rename(_ diagramID: UUID, name: String) {
        guard var diagram = store.generatedDiagrams[diagramID] else { return }
        diagram.name = name
        diagram.isNameUserDefined = true
        diagram.lastModified = Date()
        store.saveGeneratedDiagram(diagram)
        notify()
    }

    func remove(_ diagramID: UUID) {
        for i in store.projects.indices {
            store.projects[i].generatedDiagramIDs.removeAll { $0 == diagramID }
        }
        store.deleteGeneratedDiagramFile(diagramID)
        persist()
    }

    /// Applies `transform` to the stored diagram, re-auto-names it (unless user-renamed), bumps
    /// `lastModified`, persists the diagram, and notifies. `clearPositions` drops saved node
    /// positions when the configuration change can alter the node set.
    func mutate(_ diagramID: UUID, clearPositions: Bool, _ transform: (inout GeneratedDiagram) -> Void) {
        guard var diagram = store.generatedDiagrams[diagramID] else { return }
        transform(&diagram)
        if clearPositions {
            diagram.nodePositions = [:]
        }
        if !diagram.isNameUserDefined {
            diagram.name = diagram.autoName(codebaseName: codebaseName(diagram.codebaseID))
        }
        diagram.lastModified = Date()
        store.saveGeneratedDiagram(diagram)
        notify()
    }

    private func codebaseName(_ codebaseID: UUID) -> String {
        for project in store.projects {
            if let codebase = project.codebases.first(where: { $0.id == codebaseID }) { return codebase.name }
        }
        return ""
    }
}

/// Project/codebase lifecycle: CRUD, reindexing, and per-codebase quality-check rules. Carved
/// out of `ProjectBrowserViewModel` for a single responsibility; shares the store + change hooks.
@MainActor
struct ProjectCodebaseEditor {
    let store: ProjectStore
    /// Saves the whole store and notifies (used when the project/codebase set changes).
    let persist: () -> Void
    /// Notifies observers without a full save.
    let notify: () -> Void
    /// Drops a codebase's cached analysis, so its code-quality check recomputes after a rules change
    /// the analysis token can't see (an in-place edit that keeps the same rules path).
    let invalidateAnalysis: (UUID) -> Void

    // MARK: Projects

    func addProject(title: String, subtitle: String) {
        store.projects.append(Project(title: title, subtitle: subtitle, codebases: []))
        persist()
    }

    func updateProject(id: UUID, title: String, subtitle: String) {
        guard let index = store.projects.firstIndex(where: { $0.id == id }) else { return }
        store.projects[index].title = title
        store.projects[index].subtitle = subtitle
        persist()
    }

    func removeProject(_ projectID: UUID) {
        guard let project = store.projects.first(where: { $0.id == projectID }) else { return }
        for did in project.generatedDiagramIDs { store.deleteGeneratedDiagramFile(did) }
        for did in project.freeformDiagramIDs { store.deleteFreeformDiagramFile(did) }
        store.deleteProjectFile(projectID)
        store.projects.removeAll { $0.id == projectID }
        persist()
    }

    // MARK: Codebases

    func addCodebase(to projectID: UUID, name: String, directoryURL: URL) {
        guard let index = store.projects.firstIndex(where: { $0.id == projectID }) else { return }
        store.projects[index].codebases.append(Codebase(name: name, directoryPath: directoryURL.path))
        persist()
    }

    func updateCodebase(id: UUID, name: String) {
        for i in store.projects.indices {
            if let j = store.projects[i].codebases.firstIndex(where: { $0.id == id }) {
                store.projects[i].codebases[j].name = name
                persist()
                return
            }
        }
    }

    func removeCodebase(_ codebaseID: UUID) {
        for i in store.projects.indices {
            store.projects[i].codebases.removeAll { $0.id == codebaseID }
            let toRemove = store.projects[i].generatedDiagramIDs.filter { did in
                store.generatedDiagrams[did]?.codebaseID == codebaseID
            }
            for did in toRemove {
                store.projects[i].generatedDiagramIDs.removeAll { $0 == did }
                store.deleteGeneratedDiagramFile(did)
            }
        }
        store.deleteArtifactFile(for: codebaseID)
        store.deleteManagedRules(forCodebase: codebaseID)
        persist()
    }

    func reindex(codebaseID: UUID) async {
        guard let codebase = codebase(for: codebaseID) else { return }
        let url = URL(fileURLWithPath: codebase.directoryPath).standardizedFileURL
        do {
            let newArtifact = try await Task.detached(priority: .userInitiated) {
                try CodebaseAnalyzer().enrichedArtifact(at: url)
            }.value
            // Re-resolve indices after the suspension — the user may have mutated the project/codebase
            // list during the (potentially long) analysis, invalidating any pre-`await` indices.
            guard let pIndex = store.projects.firstIndex(where: { $0.id == projectID(for: codebaseID) }),
                  let cIndex = store.projects[pIndex].codebases.firstIndex(where: { $0.id == codebaseID })
            else { return }
            store.projects[pIndex].codebases[cIndex].hasArtifact = true
            store.projects[pIndex].codebases[cIndex].lastIndexed = Date()
            store.projects[pIndex].codebases[cIndex].hasParseErrors = newArtifact.metadata.hasParseErrors
            store.projects[pIndex].codebases[cIndex].parseDiagnosticCount = newArtifact.metadata.parseDiagnostics.count
            store.saveArtifact(newArtifact, for: codebaseID)
            persistProject(store.projects[pIndex].id)
        } catch {
            store.report("Reindex failed: \(error.localizedDescription)")
        }
    }

    // MARK: Quality-check rules

    /// Points a codebase's code-quality check at an external YAML rules file.
    func setQualityCheckRulesPath(codebaseID: UUID, path: String) {
        mutateCodebase(codebaseID) { $0.qualityCheck = QualityCheckConfiguration(rulesPath: path) }
        invalidateAnalysis(codebaseID)
    }

    /// Persists UI-authored rules to the codebase's managed YAML file and points its check there.
    func saveAuthoredRules(codebaseID: UUID, rules: QualityRules) {
        do {
            let url = try store.saveManagedRules(rules, forCodebase: codebaseID)
            mutateCodebase(codebaseID) { $0.qualityCheck = QualityCheckConfiguration(rulesPath: url.path) }
            invalidateAnalysis(codebaseID)
        } catch {
            store.report("Failed to save quality rules: \(error.localizedDescription)")
        }
    }

    /// The rules to seed the form editor with: the codebase's managed rules when app-managed,
    /// otherwise an empty rule set (external files are referenced, not form-edited).
    func loadEditableRules(codebaseID: UUID) -> QualityRules {
        guard let path = codebase(for: codebaseID)?.qualityCheck?.rulesPath, store.isManaged(path: path)
        else { return QualityRules() }
        return store.loadManagedRules(forCodebase: codebaseID) ?? QualityRules()
    }

    // MARK: Helpers

    private func mutateCodebase(_ codebaseID: UUID, _ transform: (inout Codebase) -> Void) {
        for i in store.projects.indices {
            if let j = store.projects[i].codebases.firstIndex(where: { $0.id == codebaseID }) {
                transform(&store.projects[i].codebases[j])
                persistProject(store.projects[i].id)
                return
            }
        }
    }

    private func persistProject(_ projectID: UUID) {
        if let project = store.projects.first(where: { $0.id == projectID }) { store.saveProject(project) }
        notify()
    }

    private func codebase(for codebaseID: UUID) -> Codebase? {
        for project in store.projects {
            if let codebase = project.codebases.first(where: { $0.id == codebaseID }) { return codebase }
        }
        return nil
    }

    private func projectID(for codebaseID: UUID) -> UUID? {
        store.projects.first { $0.codebases.contains { $0.id == codebaseID } }?.id
    }
}

/// Create/update/delete operations for freeform diagrams.
@MainActor
struct FreeformDiagramEditor {
    let store: ProjectStore
    let persist: () -> Void
    let notify: () -> Void

    func add(to projectID: UUID, name: String) -> UUID? {
        guard let projectIndex = store.projects.firstIndex(where: { $0.id == projectID }) else { return nil }
        let diagram = FreeformDiagram(name: name)
        store.projects[projectIndex].freeformDiagramIDs.append(diagram.id)
        store.saveFreeformDiagram(diagram)
        persist()
        return diagram.id
    }

    func update(diagramID: UUID, diagram: FreeformDiagram) {
        var updated = diagram
        updated.lastModified = Date()
        store.saveFreeformDiagram(updated)
        notify()
    }

    func rename(_ diagramID: UUID, name: String) {
        guard var diagram = store.freeformDiagrams[diagramID] else { return }
        diagram.name = name
        diagram.lastModified = Date()
        store.saveFreeformDiagram(diagram)
        notify()
    }

    func remove(_ diagramID: UUID) {
        for i in store.projects.indices {
            store.projects[i].freeformDiagramIDs.removeAll { $0 == diagramID }
        }
        store.deleteFreeformDiagramFile(diagramID)
        persist()
    }
}
