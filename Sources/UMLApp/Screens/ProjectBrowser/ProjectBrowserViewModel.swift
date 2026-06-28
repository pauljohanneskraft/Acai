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
        store.deleteManagedRules(forCodebase: codebaseID)
        persistChanges()
    }

    // MARK: - Architecture check (per codebase)

    /// Points a codebase's architecture check at an external YAML rules file (the path the user chose).
    func setArchitectureCheckRulesPath(codebaseID: UUID, path: String) {
        mutateCodebase(codebaseID) { $0.architectureCheck = ArchitectureCheckConfiguration(rulesPath: path) }
    }

    /// Persists UI-authored rules to the codebase's managed YAML file and points its check at that file.
    /// Surfaces a write failure through the store's error channel rather than throwing to the caller.
    func saveAuthoredRules(codebaseID: UUID, rules: ConformanceRules) {
        do {
            let url = try store.saveManagedRules(rules, forCodebase: codebaseID)
            mutateCodebase(codebaseID) { $0.architectureCheck = ArchitectureCheckConfiguration(rulesPath: url.path) }
        } catch {
            store.report("Failed to save architecture rules: \(error.localizedDescription)")
        }
    }

    /// The rules to seed the form editor with: the codebase's managed rules if its check is
    /// app-managed, otherwise an empty rule set (external files are referenced, not form-edited).
    func loadEditableRules(codebaseID: UUID) -> ConformanceRules {
        guard let path = codebase(for: codebaseID)?.architectureCheck?.rulesPath, store.isManaged(path: path)
        else { return ConformanceRules() }
        return store.loadManagedRules(forCodebase: codebaseID) ?? ConformanceRules()
    }

    /// Applies `transform` to a stored codebase in place and persists its owning project.
    private func mutateCodebase(_ codebaseID: UUID, _ transform: (inout Codebase) -> Void) {
        for i in store.projects.indices {
            if let j = store.projects[i].codebases.firstIndex(where: { $0.id == codebaseID }) {
                transform(&store.projects[i].codebases[j])
                persistProject(store.projects[i].id)
                return
            }
        }
    }

    func reindex(codebaseID: UUID) async {
        guard let codebase = codebase(for: codebaseID) else { return }
        let url = URL(fileURLWithPath: codebase.directoryPath).standardizedFileURL

        do {
            let newArtifact = try await Task.detached(priority: .userInitiated) {
                try CodebaseAnalyzer().enrichedArtifact(at: url)
            }.value
            // Re-resolve indices after the suspension — the user may have deleted or reordered
            // projects/codebases during the (potentially long) analysis, which would make any
            // indices captured before the `await` point at the wrong codebase or out of bounds.
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

    /// Applies `transform` to the stored diagram, then re-auto-names it (unless the user renamed it),
    /// bumps `lastModified`, persists, and notifies. `clearPositions` drops saved node positions when
    /// the configuration change can alter the node set.
    private func mutateDiagram(
        _ diagramID: UUID,
        clearPositions: Bool,
        _ transform: (inout GeneratedDiagram) -> Void
    ) {
        guard var diagram = store.generatedDiagrams[diagramID] else { return }
        transform(&diagram)
        if clearPositions {
            diagram.nodePositions = [:]
        }
        if !diagram.isNameUserDefined {
            diagram.name = diagram.autoName(codebaseName: codebase(for: diagram.codebaseID)?.name ?? "")
        }
        diagram.lastModified = Date()
        store.saveGeneratedDiagram(diagram)
        objectWillChange.send()
    }

    /// Updates the entry-point configuration of a sequence diagram and clears its saved
    /// participant positions (the participant set may have changed).
    func updateSequenceConfiguration(diagramID: UUID, configuration: SequenceDiagramConfiguration) {
        mutateDiagram(diagramID, clearPositions: true) { $0.sequenceConfiguration = configuration }
    }

    /// Updates the scope of a call graph and clears its saved node positions (the method set
    /// changes with scope).
    func updateCallGraphScope(diagramID: UUID, scope: CallGraphScope) {
        mutateDiagram(diagramID, clearPositions: true) { $0.callGraphScope = scope }
    }

    /// Updates the variable configuration of a state diagram and clears its saved
    /// node positions (the state set may have changed).
    func updateStateConfiguration(diagramID: UUID, configuration: StateDiagramConfiguration) {
        mutateDiagram(diagramID, clearPositions: true) { $0.stateConfiguration = configuration }
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

    /// Updates the rendering configuration of a class diagram (no-op for other types). Positions are
    /// kept — a render-option change never alters the type set.
    func updateClassDiagramConfiguration(diagramID: UUID, configuration: ClassDiagramConfiguration) {
        mutateDiagram(diagramID, clearPositions: false) { $0.classConfiguration = configuration }
    }

    // MARK: - Delta comparison (git revision)

    /// Identity of a cached comparison snapshot: which directory at which git ref.
    private struct ComparisonKey: Hashable {
        let directory: String
        let ref: String
    }

    /// Cached "old"-side artifacts for delta mode, keyed by codebase directory + git ref. Populated
    /// asynchronously by `ensureComparisonLoaded`; read through `comparisonArtifact(for:)`.
    @Published private var comparisonArtifacts: [ComparisonKey: CodeArtifact] = [:]
    /// Most recent comparison load error, surfaced near the picker.
    @Published private(set) var comparisonError: String?

    /// Sets (or clears, with `nil`) the git revision a diagram is compared against in delta mode,
    /// dropping saved positions since the rendered element set changes between normal and union.
    func updateComparisonGitRef(diagramID: UUID, ref: String?) {
        comparisonError = nil
        mutateDiagram(diagramID, clearPositions: true) {
            $0.comparisonGitRef = (ref?.isEmpty == true) ? nil : ref
        }
    }

    /// The cached "old" artifact for a diagram's current comparison ref, if already loaded.
    func comparisonArtifact(for diagram: GeneratedDiagram) -> CodeArtifact? {
        guard let ref = diagram.comparisonGitRef,
              let directory = codebase(for: diagram.codebaseID)?.directoryPath
        else { return nil }
        return comparisonArtifacts[ComparisonKey(directory: directory, ref: ref)]
    }

    /// Loads the "old" artifact for a diagram's comparison ref via a read-only `git archive`
    /// snapshot, caching it. A no-op when delta mode is off or the snapshot is already cached.
    func ensureComparisonLoaded(for diagram: GeneratedDiagram) async {
        guard let ref = diagram.comparisonGitRef,
              let directory = codebase(for: diagram.codebaseID)?.directoryPath
        else { return }
        let key = ComparisonKey(directory: directory, ref: ref)
        guard comparisonArtifacts[key] == nil else { return }
        let url = URL(fileURLWithPath: directory).standardizedFileURL
        do {
            let artifact = try await Task.detached(priority: .userInitiated) {
                try GitRevisionSnapshot(directory: url, reference: ref).artifact()
            }.value
            comparisonArtifacts[key] = artifact
            comparisonError = nil
        } catch {
            comparisonError = error.localizedDescription
        }
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
        guard let artifact = store.artifact(for: codebaseID)?.resolvingExtensions() else { return nil }
        guard let filter = artifact.standardLanguageConfiguration.generatedCodeFilter else { return artifact }
        return artifact.filteringGeneratedTypes(using: filter)
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
