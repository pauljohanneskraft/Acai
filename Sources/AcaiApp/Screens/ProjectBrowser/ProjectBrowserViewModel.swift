import Foundation
import SwiftUI
import AcaiLibrary
import AcaiCore
import AcaiDiagram
import AcaiRender

@MainActor
final class ProjectBrowserViewModel: ObservableObject {
    @Published var store: ProjectStore
    @Published var selection: Selection?
    /// A rendered image/DOT/Mermaid export waiting to be written, driving the single `.fileExporter`
    /// modifier in `ProjectBrowserView` (cross-platform: `.fileExporter` replaces the old
    /// macOS-only `NSSavePanel` calls). See `ProjectBrowserViewModel+Export.swift`.
    @Published var pendingExport: PendingExport?

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
        // `withAnimation` here isn't cosmetic: without an active transaction, removing a row from
        // the sidebar's `List`/`DisclosureGroup` outline can leave stale "ghost" child rows behind
        // (a SwiftUI/AppKit outline-diffing quirk) until an unrelated selection change forces a full
        // reload. Wrapping the notify in a transaction makes the outline view compute a proper
        // insert/remove diff instead.
        withAnimation {
            pruneDanglingSelection()
            objectWillChange.send()
        }
    }

    /// Clears `selection` when it points at a project/codebase/diagram that no longer exists (e.g.
    /// after a delete), so the detail pane falls back to the empty state instead of a dead-end
    /// "not found" message.
    private func pruneDanglingSelection() {
        switch selection {
        case .project(let id):
            if !store.projects.contains(where: { $0.id == id }) { selection = nil }
        case .codebase(let id):
            if codebase(for: id) == nil { selection = nil }
        case .generatedDiagram(let id):
            if store.generatedDiagrams[id] == nil { selection = nil }
        case .freeformDiagram(let id):
            if store.freeformDiagrams[id] == nil { selection = nil }
        case .none:
            break
        }
    }

    // MARK: - Project / Codebase lifecycle

    /// Project/codebase CRUD, reindexing, and per-codebase quality-check rules. Carved out of
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

    /// Loads the "old" artifact for a diagram's comparison ref via a read-only `git archive`
    /// snapshot, caching it. A no-op when delta mode is off or the snapshot is already cached.
    func ensureComparisonLoaded(for diagram: GeneratedDiagram) async {
        guard let codebase = codebase(for: diagram.codebaseID),
              let ref = diagram.comparisonGitRef
        else { return }
        let directory = codebase.directoryPath
        let fileFilter = codebase.fileFilter
        let key = ComparisonKey(directory: directory, ref: ref)
        guard comparisonArtifacts[key] == nil else { return }
        let url = URL(fileURLWithPath: directory).standardizedFileURL
        do {
            let semantic = try await Task.detached(priority: .userInitiated) {
                try GitRevisionSnapshot(directory: url, reference: ref).artifact(fileFilter: fileFilter)
            }.value
            // Flatten to the same diagram-ready form as the current-side artifact so delta mode
            // diffs like-for-like (node ids must match the flattened display artifact).
            comparisonArtifacts[key] = CodebaseAnalyzer().flattenedForDisplay(semantic)
            comparisonError = nil
        } catch {
            comparisonError = error.localizedDescription
        }
    }

    /// The cached "old" artifact for a diagram's current comparison ref, if already loaded.
    func comparisonArtifact(for diagram: GeneratedDiagram) -> CodeArtifact? {
        guard let ref = diagram.comparisonGitRef,
              let directory = codebase(for: diagram.codebaseID)?.directoryPath
        else { return nil }
        return comparisonArtifacts[ComparisonKey(directory: directory, ref: ref)]
    }

    /// Memoised diagram-ready (flattened) form of each codebase's stored semantic artifact, keyed by
    /// codebase and stamped with its `lastIndexed` so a reindex invalidates it. Not `@Published`: it
    /// is a pure derivation of the stored artifact filled lazily on read (often during a view update),
    /// so mutating it must not trigger `objectWillChange`.
    private var displayArtifactCache: [UUID: (stamp: Date?, artifact: CodeArtifact)] = [:]

    func generatedDiagram(for diagramID: UUID) -> GeneratedDiagram? {
        store.generatedDiagrams[diagramID]
    }

    // MARK: - Codebase analysis (metrics + scans)

    /// Identity of a cached analysis: it stays valid until the codebase is reindexed (`lastIndexed`),
    /// its quality-check configuration changes, or it is explicitly invalidated (`revision`,
    /// bumped for an in-place managed-rules edit that keeps the same path). The detail view keys its
    /// `.task` on this, so any change re-triggers the background recompute.
    struct AnalysisToken: Equatable {
        let lastIndexed: Date?
        let configuration: QualityCheckConfiguration?
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
            configuration: codebase?.qualityCheck,
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
        guard let artifact = semanticArtifact(for: codebaseID) else { return }
        analyses[codebaseID] = .computing(token)
        let configuration = codebase.qualityCheck
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

    func codebase(for codebaseID: UUID) -> Codebase? {
        for p in store.projects {
            if let c = p.codebases.first(where: { $0.id == codebaseID }) {
                return c
            }
        }
        return nil
    }

    /// The diagram-ready (flattened) artifact the detail view, diagram views and export render from:
    /// nested types are hoisted to the top level with qualified names, generated types filtered out.
    /// Memoised per codebase (stamped with `lastIndexed`) since it is read on every view update.
    func artifact(for codebaseID: UUID) -> CodeArtifact? {
        guard let semantic = store.artifact(for: codebaseID) else { return nil }
        let stamp = codebase(for: codebaseID)?.lastIndexed
        if let cached = displayArtifactCache[codebaseID], cached.stamp == stamp {
            return cached.artifact
        }
        let display = CodebaseAnalyzer()
            .flattenedForDisplay(semantic)
            .filteringGeneratedTypes(using: semantic.standardLanguageResolver)
        displayArtifactCache[codebaseID] = (stamp, display)
        return display
    }

    /// The **semantic** (un-flattened) artifact used for metrics and scans: nested types are
    /// preserved so nesting depth and other tree-shaped metrics are computed correctly. Returned
    /// unfiltered — `CodebaseAnalysis` applies generated-type filtering once, driven by the quality
    /// rules' `includeGeneratedTypes` (default: exclude), so the whole statistics pane stays
    /// consistent and matches the CLI/MCP.
    func semanticArtifact(for codebaseID: UUID) -> CodeArtifact? {
        store.artifact(for: codebaseID)
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
