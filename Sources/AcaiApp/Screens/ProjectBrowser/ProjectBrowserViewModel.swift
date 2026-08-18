import Foundation
import SwiftUI
import AcaiGit
import AcaiLibrary
import AcaiCore
import AcaiDiagram
import AcaiRender

@MainActor
final class ProjectBrowserViewModel: ObservableObject {
    @Published var store: ProjectStore
    @Published var selection: Selection?
    @Published var pendingExport: PendingExport?

    enum Selection: Hashable {
        case project(UUID)
        case codebase(UUID)
        case generatedDiagram(UUID)
        case freeformDiagram(UUID)
        /// Identified by its credential-free remote URL.
        case repository(URL)
        case findings(UUID)
    }

    /// `[weak self]`: the coordinator outlives no particular `editing` snapshot, so it always
    /// resolves a fresh one per reindex.
    private(set) lazy var fileWatchCoordinator = FileWatchReindexCoordinator { [weak self] id in
        await self?.editing.reindex(codebaseID: id)
    }

    /// macOS drives this with a periodic sweep (`startScheduledRefresh()`); iOS drives it one
    /// codebase per `BGAppRefreshTask` wake instead (`ScheduledRefreshTaskRunner`, also started
    /// from `startScheduledRefresh()`).
    private(set) lazy var scheduledRefreshCoordinator = ScheduledRefreshCoordinator(store: store) { [weak self] id in
        await self?.editing.pull(codebaseID: id)
    }
    #if os(iOS)
    private(set) lazy var scheduledRefreshTaskRunner = ScheduledRefreshTaskRunner(
        coordinator: scheduledRefreshCoordinator)
    #endif
    private var didStartScheduledRefresh = false

    init(store: ProjectStore = ProjectStore()) {
        self.store = store
        fileWatchCoordinator.sync(codebases: store.projects.flatMap(\.codebases))
    }

    /// Starts the scheduled-refresh mechanism appropriate to the current platform. Idempotent —
    /// safe to call from a view's `.task`, which may run again if the view is recreated.
    func startScheduledRefresh() {
        guard !didStartScheduledRefresh else { return }
        didStartScheduledRefresh = true
        #if os(macOS)
        scheduledRefreshCoordinator.startPeriodicSweep(interval: .seconds(15 * 60))
        #else
        scheduledRefreshTaskRunner.register()
        scheduledRefreshTaskRunner.scheduleNext()
        #endif
    }

    func persistChanges() {
        store.save()
        fileWatchCoordinator.sync(codebases: store.projects.flatMap(\.codebases))
        // `withAnimation` isn't cosmetic: without an active transaction, removing a row from the
        // sidebar's `List`/`DisclosureGroup` outline can leave stale "ghost" child rows behind until
        // an unrelated selection change forces a full reload.
        withAnimation {
            pruneDanglingSelection()
            objectWillChange.send()
        }
    }

    /// Clears `selection` when it points at a project/codebase/diagram/repository that no longer
    /// exists (e.g. after a delete), so the detail pane falls back to the empty state instead of a
    /// dead-end "not found" message.
    private func pruneDanglingSelection() {
        guard let selection, !selectionStillExists(selection) else { return }
        self.selection = nil
    }

    private func selectionStillExists(_ selection: Selection) -> Bool {
        switch selection {
        case .project(let id):
            store.projects.contains { $0.id == id }
        case .codebase(let id):
            codebase(for: id) != nil
        case .generatedDiagram(let id):
            store.generatedDiagrams[id] != nil
        case .freeformDiagram(let id):
            store.freeformDiagrams[id] != nil
        case .repository(let remoteURL):
            repositoryIndex().contains { $0.remoteURL == remoteURL }
        case .findings(let projectID):
            store.projects.contains { $0.id == projectID }
        }
    }

    // MARK: - Project / Codebase lifecycle

    var editing: ProjectCodebaseEditor {
        ProjectCodebaseEditor(
            store: store,
            persist: { [weak self] in self?.persistChanges() },
            notify: { [weak self] in self?.objectWillChange.send() },
            invalidateAnalysis: { [weak self] id in self?.invalidateAnalysis(codebaseID: id) }
        )
    }

    // MARK: - Generated Diagram CRUD

    var diagrams: GeneratedDiagramEditor {
        GeneratedDiagramEditor(
            store: store,
            persist: { [weak self] in self?.persistChanges() },
            notify: { [weak self] in self?.objectWillChange.send() }
        )
    }

    // MARK: - Delta comparison (git revision) — state; behavior in +Comparison.swift

    /// Cached artifacts for delta mode, **semantic** (un-flattened, matching `semanticArtifact(for:)`
    /// — flattening happens at read, in `displayArtifact(for:)`), keyed by codebase directory +
    /// resolved git ref. Populated asynchronously by `ensureComparisonLoaded`.
    @Published var comparisonArtifacts: [ComparisonKey: CodeArtifact] = [:]
    /// Flattened, display-ready derivation of `comparisonArtifacts`, filled lazily on read — mirrors
    /// `displayArtifactCache`'s "not `@Published`, pure derivation" reasoning below.
    var comparisonDisplayCache: [ComparisonKey: CodeArtifact] = [:]
    /// Resolved merge-base SHAs for pull-request comparisons, populated by `ensureComparisonLoaded`.
    @Published var resolvedMergeBases: [MergeBaseKey: String] = [:]

    /// Most recent comparison load error, surfaced near the picker.
    @Published var comparisonError: String?

    /// Files the user has checked off in a diagram's Compare panel changed-files list, and findings
    /// they've checked off in its "New findings" list — an in-memory, per-session reading aid, never
    /// persisted, keyed by diagram id. Reset by `updateComparisonGitRef`/`selectComparisonPullRequest`.
    @Published var comparisonReviewedFiles: [UUID: Set<String>] = [:]
    @Published var comparisonReviewedFindings: [UUID: Set<String>] = [:]

    /// Cached quality/dead-code/health analysis of `comparisonSemanticArtifact(for:)`, for the
    /// Compare panel's findings delta. Populated asynchronously by `ensureComparisonAnalysisLoaded`.
    @Published var comparisonAnalyses: [ComparisonKey: CodebaseAnalysis] = [:]

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

    func analysisToken(for codebaseID: UUID) -> AnalysisToken {
        let codebase = codebase(for: codebaseID)
        return AnalysisToken(
            lastIndexed: codebase?.lastIndexed,
            configuration: codebase?.qualityCheck,
            revision: analysisRevisions[codebaseID, default: 0])
    }

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

    func repositoryIndex() -> [RepositoryIndexEntry] {
        RepositoryIndex(projects: store.projects).entries()
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

    func generatedDiagramsForProject(_ projectID: UUID) -> [GeneratedDiagram] {
        guard let project = store.projects.first(where: { $0.id == projectID }) else { return [] }
        return project.generatedDiagramIDs.compactMap { store.generatedDiagrams[$0] }
    }

    func freeformDiagramsForProject(_ projectID: UUID) -> [FreeformDiagram] {
        guard let project = store.projects.first(where: { $0.id == projectID }) else { return [] }
        return project.freeformDiagramIDs.compactMap { store.freeformDiagrams[$0] }
    }
}
