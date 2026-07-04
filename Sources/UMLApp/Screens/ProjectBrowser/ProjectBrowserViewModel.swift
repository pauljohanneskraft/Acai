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

    // MARK: - Project / Codebase lifecycle

    /// Project/codebase CRUD, reindexing, and per-codebase architecture-check rules. Carved out of
    /// this view model (see ``GeneratedDiagramEditor``); shares the store + change notifications.
    var editing: ProjectCodebaseEditor {
        ProjectCodebaseEditor(
            store: store,
            persist: { [weak self] in self?.persistChanges() },
            notify: { [weak self] in self?.objectWillChange.send() },
            invalidateAnalysis: { [weak self] id in self?.invalidateAnalysis(codebaseID: id) }
        )
    }

    // MARK: - Generated Diagram CRUD

    /// Create/update/delete operations for generated diagrams. Carved out of this view model so it
    /// keeps a single responsibility; shares the same store + change notifications.
    var diagrams: GeneratedDiagramEditor {
        GeneratedDiagramEditor(
            store: store,
            persist: { [weak self] in self?.persistChanges() },
            notify: { [weak self] in self?.objectWillChange.send() }
        )
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
        diagrams.mutate(diagramID, clearPositions: true) {
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

    func generatedDiagram(for diagramID: UUID) -> GeneratedDiagram? {
        store.generatedDiagrams[diagramID]
    }

    // MARK: - Codebase analysis (metrics + scans)

    /// Identity of a cached analysis: it stays valid until the codebase is reindexed (`lastIndexed`),
    /// its architecture-check configuration changes, or it is explicitly invalidated (`revision`,
    /// bumped for an in-place managed-rules edit that keeps the same path). The detail view keys its
    /// `.task` on this, so any change re-triggers the background recompute.
    struct AnalysisToken: Equatable {
        let lastIndexed: Date?
        let configuration: ArchitectureCheckConfiguration?
        let revision: Int
    }

    /// A codebase's analysis is either being computed in the background or ready. The token it was
    /// keyed on is kept so a stale entry (after a reindex during computation) is recomputed.
    private enum AnalysisState {
        case computing(AnalysisToken)
        case ready(AnalysisToken, CodebaseAnalysis)
    }

    /// Cached per-codebase analyses, populated asynchronously by `ensureAnalysisLoaded`; read through
    /// `analysis(for:)`. In-memory only — recomputed on demand rather than persisted.
    @Published private var analyses: [UUID: AnalysisState] = [:]
    /// Bumped by `invalidateAnalysis` to force a recompute when the token's other fields can't see the
    /// change (an in-place managed-rules edit keeps the same rules path and reindex date).
    private var analysisRevisions: [UUID: Int] = [:]

    /// The current analysis identity for a codebase — the detail view keys its `.task` on this value.
    func analysisToken(for codebaseID: UUID) -> AnalysisToken {
        let codebase = codebase(for: codebaseID)
        return AnalysisToken(
            lastIndexed: codebase?.lastIndexed,
            configuration: codebase?.architectureCheck,
            revision: analysisRevisions[codebaseID, default: 0])
    }

    /// The cached analysis for a codebase, or `nil` while it is still being computed (or absent).
    func analysis(for codebaseID: UUID) -> CodebaseAnalysis? {
        if case .ready(_, let analysis) = analyses[codebaseID] { return analysis }
        return nil
    }

    /// Computes and caches a codebase's analysis on a background thread. A no-op when a matching
    /// (same token) result is already cached or in flight.
    func ensureAnalysisLoaded(codebaseID: UUID) async {
        guard let codebase = codebase(for: codebaseID) else { return }
        let token = analysisToken(for: codebaseID)
        switch analyses[codebaseID] {
        case .ready(let cached, _) where cached == token:
            return  // already current for this token
        case .computing(let cached) where cached == token:
            return  // already in flight for this token
        default:
            break
        }
        guard let artifact = artifact(for: codebaseID) else { return }
        analyses[codebaseID] = .computing(token)
        let configuration = codebase.architectureCheck
        let analysis = await Task.detached(priority: .userInitiated) {
            CodebaseAnalysis(artifact: artifact, configuration: configuration)
        }.value
        // A reindex / config edit / invalidation during the computation supersedes this result; the
        // view's `.task` will have re-fired for the new token.
        guard analysisToken(for: codebaseID) == token else { return }
        analyses[codebaseID] = .ready(token, analysis)
    }

    /// Drops a codebase's cached analysis and bumps its revision, forcing a recompute. Used when a
    /// change the token can't otherwise see (an in-place rules-file edit) invalidates the check.
    func invalidateAnalysis(codebaseID: UUID) {
        analysisRevisions[codebaseID, default: 0] += 1
        analyses.removeValue(forKey: codebaseID)
    }

    // MARK: - Freeform Diagram CRUD

    /// Create/update/delete operations for freeform diagrams (see ``GeneratedDiagramEditor``).
    var freeforms: FreeformDiagramEditor {
        FreeformDiagramEditor(
            store: store,
            persist: { [weak self] in self?.persistChanges() },
            notify: { [weak self] in self?.objectWillChange.send() }
        )
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
