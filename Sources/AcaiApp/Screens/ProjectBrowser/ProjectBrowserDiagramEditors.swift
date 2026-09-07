import CoreGraphics
import Foundation
import AcaiCore
import AcaiDiagram
import AcaiGit
import AcaiLibrary
import AcaiRender
import AcaiQuality

// Diagram-management collaborators carved out of `ProjectBrowserViewModel` (it had grown into a
// god-object). Each is a thin value over the shared `ProjectStore` reference plus the owning view
// model's change hooks, so behaviour is identical: `persist` = save + `objectWillChange`, `notify`
// = `objectWillChange` only. The view model exposes them as `diagrams` / `freeforms`; views call
// e.g. `model.diagrams.rename(...)`.

@MainActor
struct GeneratedDiagramEditor {
    let store: ProjectStore
    let persist: () -> Void
    let notify: () -> Void

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

    func updateStateConfiguration(diagramID: UUID, configuration: StateDiagramConfiguration) {
        mutate(diagramID, clearPositions: true) { $0.stateConfiguration = configuration }
    }

    /// Updates the rendering configuration of a class diagram (positions kept — a render-option change
    /// never alters the type set).
    func updateClassDiagramConfiguration(diagramID: UUID, configuration: ClassDiagramConfiguration) {
        mutate(diagramID, clearPositions: false) { $0.classConfiguration = configuration }
    }

    /// Updates a package diagram's selector filter. Positions are kept: filtering only removes
    /// nodes/edges, it never changes what a surviving node's saved position means.
    func updatePackageDiagramFilter(diagramID: UUID, filter: AcaiQuality.Selector?) {
        mutate(diagramID, clearPositions: false) { $0.packageDiagramFilter = filter }
    }

    func updateCallGraphFilter(diagramID: UUID, filter: AcaiQuality.Selector?) {
        mutate(diagramID, clearPositions: false) { $0.callGraphFilter = filter }
    }

    /// Updates a sequence diagram's selector filter, keeping the rest of the configuration and —
    /// unlike `updateSequenceConfiguration` — the saved positions, since filtering only removes
    /// participants/messages.
    func updateSequenceFilter(diagramID: UUID, filter: AcaiQuality.Selector?) {
        mutate(diagramID, clearPositions: false) { $0.sequenceConfiguration?.filter = filter }
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
        store.removeFromRecentlyViewed(.generatedDiagram(diagramID))
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

@MainActor
struct ProjectCodebaseEditor {
    let store: ProjectStore
    let persist: () -> Void
    let notify: () -> Void
    /// Drops a codebase's cached analysis, so its code-quality check recomputes after a rules change
    /// the analysis token can't see (an in-place edit that keeps the same rules path).
    let invalidateAnalysis: (UUID) -> Void
    /// Real network clone/fetch, swapped for `FixtureGitHubRepositoryService` under a UI test
    /// fixture — see `GitHubRepositoryService`.
    var repositoryService: GitHubRepositoryService = GitHubRepositoryServiceResolver().resolve()

    // MARK: Projects

    @discardableResult
    func addProject(title: String, subtitle: String) -> UUID {
        let project = Project(title: title, subtitle: subtitle, codebases: [])
        store.projects.append(project)
        persist()
        return project.id
    }

    func removeProject(_ projectID: UUID) {
        guard let project = store.projects.first(where: { $0.id == projectID }) else { return }
        for did in project.generatedDiagramIDs {
            store.deleteGeneratedDiagramFile(did)
            store.removeFromRecentlyViewed(.generatedDiagram(did))
        }
        for did in project.freeformDiagramIDs {
            store.deleteFreeformDiagramFile(did)
            store.removeFromRecentlyViewed(.freeformDiagram(did))
        }
        for codebase in project.codebases {
            store.removeFromRecentlyViewed(.codebase(codebase.id))
        }
        store.deleteProjectFile(projectID)
        store.projects.removeAll { $0.id == projectID }
        persist()
        triggerSpotlightReindex()
    }

    // MARK: Codebases

    /// `repository` is set when `NewCodebaseSheet`'s local-folder picker detected the picked
    /// folder is already a git working directory with an `origin` remote (the transparent
    /// upgrade, via `LocalGitRepositoryDetector`) — `nil` for a plain folder, which behaves exactly
    /// as before.
    func addCodebase(
        to projectID: UUID, name: String, directoryURL: URL,
        securityScopedBookmark: SecurityScopedBookmark? = nil, repository: CodebaseRepositoryReference? = nil
    ) {
        guard let index = store.projects.firstIndex(where: { $0.id == projectID }) else { return }
        store.projects[index].codebases.append(Codebase(
            name: name, directoryPath: directoryURL.path, securityScopedBookmark: securityScopedBookmark,
            repository: repository))
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

    /// Re-points an existing codebase at another folder — the recovery from a directory that was
    /// deleted, moved off a bookmark, or that the sandbox no longer grants access to. Updates the
    /// codebase in place rather than adding one, so its diagrams and artifact survive.
    func relocateCodebase(id: UUID, directoryURL: URL, securityScopedBookmark: SecurityScopedBookmark?) {
        mutateCodebase(id) {
            $0.directoryPath = directoryURL.path
            $0.securityScopedBookmark = securityScopedBookmark
            // The indexed artifact describes the *old* folder. Drop it up front rather than after
            // the reindex, so a reindex that fails leaves the codebase honestly un-indexed instead
            // of resolving diagrams against a path it no longer points at. The artifact *file*
            // stays until the reindex overwrites it.
            $0.hasArtifact = false
        }
        store.artifacts.removeValue(forKey: id)
        invalidateAnalysis(id)
        Task { await reindex(codebaseID: id) }
    }

    func removeCodebase(_ codebaseID: UUID) {
        let removedCodebase = codebase(for: codebaseID)
        for i in store.projects.indices {
            store.projects[i].codebases.removeAll { $0.id == codebaseID }
            let toRemove = store.projects[i].generatedDiagramIDs.filter { did in
                store.generatedDiagrams[did]?.codebaseID == codebaseID
            }
            for did in toRemove {
                store.projects[i].generatedDiagramIDs.removeAll { $0 == did }
                store.deleteGeneratedDiagramFile(did)
                store.removeFromRecentlyViewed(.generatedDiagram(did))
            }
        }
        store.deleteArtifactFile(for: codebaseID)
        store.deleteManagedRules(forCodebase: codebaseID)
        // A codebase created after worktree support existed (has both `githubSource` and
        // `repository`) has a linked worktree, not an independent clone under `githubClonesDir` —
        // remove that instead. Only the worktree goes: the shared hub clone itself stays, since
        // other codebases may still reference it (removing that is a separate, explicit
        // Repositories UI action). Older codebases (`githubSource` set, `repository` nil) keep
        // using `deleteGitHubClone`, which is a harmless no-op for every other codebase shape.
        if removedCodebase?.githubSource != nil, removedCodebase?.repository != nil {
            removeWorktree(codebaseID: codebaseID, repository: removedCodebase?.repository)
        } else {
            store.deleteGitHubClone(for: codebaseID)
        }
        store.removeFromRecentlyViewed(.codebase(codebaseID))
        persist()
        triggerSpotlightReindex()
    }

    /// Deregisters and deletes a codebase's linked worktree, leaving the shared hub clone (and any
    /// other codebase's worktree of it) untouched.
    private func removeWorktree(codebaseID: UUID, repository: CodebaseRepositoryReference?) {
        guard let repository else { return }
        let sync = GitWorktreeSync(
            transportURL: repository.remoteURL, ref: repository.ref,
            hubStoreDirectory: store.gitRepositoriesDir, locks: store.gitRepositoryLocks)
        let worktreeName = store.gitWorktreeName(for: codebaseID)
        Task { try? await sync.removeWorktree(named: worktreeName) }
    }

    // MARK: Quality-check rules

    func setQualityCheckRulesPath(
        codebaseID: UUID, path: String, securityScopedBookmark: SecurityScopedBookmark? = nil
    ) {
        mutateCodebase(codebaseID) {
            $0.qualityCheck = QualityCheckConfiguration(rulesPath: path, securityScopedBookmark: securityScopedBookmark)
        }
        invalidateAnalysis(codebaseID)
    }

    func saveAuthoredRules(codebaseID: UUID, rules: QualityRules) {
        do {
            let url = try store.saveManagedRules(rules, forCodebase: codebaseID)
            mutateCodebase(codebaseID) { $0.qualityCheck = QualityCheckConfiguration(rulesPath: url.path) }
            invalidateAnalysis(codebaseID)
        } catch {
            store.report(.app("Error.ProjectBrowserViewModel.SaveQualityRulesFailed \(error.localizedDescription)"))
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

    // Not `private`: `ProjectBrowserDiagramEditors+GitHubSync.swift`'s extension (a separate file,
    // kept there only to stay under this file's own line-count limit) needs to call these too —
    // same "not private, another file's extension needs it too" pattern used throughout this app.
    func mutateCodebase(_ codebaseID: UUID, _ transform: (inout Codebase) -> Void) {
        for i in store.projects.indices {
            if let j = store.projects[i].codebases.firstIndex(where: { $0.id == codebaseID }) {
                transform(&store.projects[i].codebases[j])
                persistProject(store.projects[i].id)
                return
            }
        }
    }

    func persistProject(_ projectID: UUID) {
        if let project = store.projects.first(where: { $0.id == projectID }) { store.saveProject(project) }
        notify()
    }

    func codebase(for codebaseID: UUID) -> Codebase? {
        for project in store.projects {
            if let codebase = project.codebases.first(where: { $0.id == codebaseID }) { return codebase }
        }
        return nil
    }

    func projectID(for codebaseID: UUID) -> UUID? {
        store.projects.first { $0.codebases.contains { $0.id == codebaseID } }?.id
    }

    /// Rebuilds the on-device Spotlight index, off the main actor. Best-effort: a failure here
    /// never surfaces to the user. Not `private`: `ProjectBrowserDiagramEditors+GitHubSync.swift` calls it too.
    func triggerSpotlightReindex() {
        // `CSSearchableIndex.default()` is system-wide and outlives the process, so a UI-test run
        // would leave the fixture's items in the real index — on a developer's own Mac as much as a
        // runner — and a later launch could be handed a continuation for them. The fixture
        // redirects storage, not Spotlight, so this has to opt out explicitly.
        guard UITestFixtureResolver().resolveBaseDir() == nil else { return }
        let builder = QuickOpenIndexBuilder(
            projects: store.projects, artifacts: store.artifacts,
            generatedDiagrams: store.generatedDiagrams, freeformDiagrams: store.freeformDiagrams
        )
        Task.detached(priority: .userInitiated) {
            try? await SpotlightIndexer().reindex(builder.entries())
        }
    }
}

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
        store.removeFromRecentlyViewed(.freeformDiagram(diagramID))
        persist()
    }
}
