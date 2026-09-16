import SwiftUI
import AcaiCore
import AcaiDiagram

struct CodebaseDetailView: View {
    let codebaseID: UUID
    @EnvironmentObject var model: ProjectBrowserViewModel
    /// Not `private`: the header extension (a separate file, kept there only to stay under this
    /// file's own line-count limit) reads these too.
    let repositoryService: GitHubRepositoryService
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.scenePhase) var scenePhase
    /// Not `private`: the header extension (a separate file, kept there only to stay under this
    /// file's own line-count limit) needs to write these too.
    @State var reindexPhase: AsyncOperationPhase = .idle
    @State var pullPhase: AsyncOperationPhase = .idle
    @State var refSwitchPhase: AsyncOperationPhase = .idle
    @State var availableRefs: [GitHubRef] = []
    /// Bumped to force a fresh staleness recheck (on appear, or the scene becoming active again);
    /// tying it to a `.task(id:)` (rather than a plain `Task { }` in `.onAppear`) means SwiftUI
    /// cancels the previous check the moment this view disappears, instead of letting it finish in
    /// the background and mutate shared state for a screen the user has already navigated away from.
    @State var freshnessRecheckTrigger = 0
    /// Not `private`: the diagram-buttons and diagram-sheets extensions (separate files, kept there
    /// only to stay under this file's own line-count limit) need to write it too.
    @State var sequenceConfigContext: ConfigContext?
    @State var stateConfigContext: ConfigContext?
    @State var callGraphConfigContext: ConfigContext?
    @State var contentWidth: CGFloat = 0
    @State var statisticDetail: StatisticDetail?
    /// Uniform card heights per grid (each = the tallest card in that grid), so cards never differ.
    @State var statCardHeight: CGFloat = 0
    @State var diagramCardHeight: CGFloat = 0
    /// Drives the destructive "Delete Codebase…" confirmation — a second, discoverable path
    /// to the same action the sidebar's context menu already offers.
    @State var showDeleteConfirmation = false

    /// Not `private`, for the same cross-file reason as the `@State` properties above.
    struct ConfigContext: Identifiable {
        let projectID: UUID
        let codebaseID: UUID
        var id: UUID { codebaseID }
    }

    /// Defaults to the real network implementation, swapped for `FixtureGitHubRepositoryService`
    /// under a UI test fixture — see `GitHubRepositoryService`.
    init(codebaseID: UUID, repositoryService: GitHubRepositoryService? = nil) {
        self.codebaseID = codebaseID
        self.repositoryService = repositoryService ?? GitHubRepositoryServiceResolver().resolve()
    }

    var codebase: Codebase? {
        model.codebase(for: codebaseID)
    }

    var artifact: CodeArtifact? {
        model.artifact(for: codebaseID)
    }

    var projectID: UUID? {
        model.projectID(for: codebaseID)
    }

    var body: some View {
        if let codebase {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerSection(codebase: codebase)

                    if let artifact {
                        diagramsBar(codebase: codebase, artifact: artifact)
                        Divider()
                        if let analysis = model.analysis(for: codebaseID) {
                            analysisSections(codebase: codebase, artifact: artifact, analysis: analysis)
                        } else {
                            analyzingPlaceholder
                            Divider()
                        }
                        if !artifact.globalVariables.isEmpty {
                            CodebaseGlobalsSection(codebase: codebase, artifact: artifact)
                            Divider()
                        }
                        if !artifact.freestandingFunctions.isEmpty {
                            CodebaseFunctionsSection(codebase: codebase, artifact: artifact)
                            Divider()
                        }
                        CodebaseTypesSection(codebase: codebase, artifact: artifact)
                        Divider()
                        CodebaseRelationshipsSection(codebase: codebase, artifact: artifact)
                    } else {
                        notIndexedSection(codebase: codebase)
                    }

                    Divider()
                    deleteCodebaseSection
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
            }
            .navigationTitle(codebase.name)
            .userActivity(CodebaseHandoffActivity.activityType) {
                CodebaseHandoffActivity(codebase: codebase).configure($0)
            }
            .task(id: model.analysisToken(for: codebaseID)) {
                await model.ensureAnalysisLoaded(codebaseID: codebaseID)
            }
            .sheet(item: $sequenceConfigContext) { context in
                sequenceConfigSheet(for: context)
            }
            .sheet(item: $stateConfigContext) { context in
                stateConfigSheet(for: context)
            }
            .sheet(item: $callGraphConfigContext) { context in
                callGraphConfigSheet(for: context)
            }
            .sheet(item: $statisticDetail) { detail in
                StatisticDetailSheet(codebase: codebase, detail: detail)
                    .environmentObject(model)
            }
            .sheet(item: $model.pendingGuidedRoute) { route in
                GuidedRouteSheet(route: route)
                    .environmentObject(model)
            }
            .confirmationDialog(
                .app("View.CodebaseDetailView.ConfirmDeleteCodebase \(codebase.name)"),
                isPresented: $showDeleteConfirmation
            ) {
                Button(.app("View.CodebaseDetailView.DeleteCodebase"), role: .destructive) {
                    model.editing.removeCodebase(codebaseID)
                }
                .accessibilityIdentifier("codebaseDetail.codebase.delete.confirmButton")
            } message: {
                Text(.app("View.CodebaseDetailView.DeletesDiagramsCachedAnalysis"))
            }
        } else {
            Text(.app("View.CodebaseDetailView.CodebaseNotFound"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Analysis-backed sections

    /// The report sections whose scans are computed once in the background (``CodebaseAnalysis``) and
    /// cached until reindex. Rendered only once the analysis is ready — until then the pane shows
    /// `analyzingPlaceholder` in their place.
    @ViewBuilder
    private func analysisSections(
        codebase: Codebase, artifact: CodeArtifact, analysis: CodebaseAnalysis
    ) -> some View {
        statisticsSection(metrics: analysis.metrics)
        Divider()
        QualityCheckSection(
            codebase: codebase, artifact: artifact,
            report: analysis.quality, usesConfiguredRules: analysis.usesConfiguredRules,
            rulesError: analysis.qualityError)
        Divider()
        DeadCodeSection(codebase: codebase, artifact: artifact, report: analysis.deadCode)
        Divider()
        ParseHealthSection(codebase: codebase, report: analysis.health)
        Divider()
    }

    private var analyzingPlaceholder: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(.app("View.CodebaseDetailView.AnalyzingCodebase"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 28)
    }

}

// Not Indexed section — kept small; the header lives in `CodebaseDetailView+Header.swift`, the
// diagram buttons/card-grid layout in `CodebaseDetailView+Diagrams.swift`, and the diagram
// configuration sheets in `CodebaseDetailView+DiagramSheets.swift` (all separate files, kept there
// only to stay under this file's own `file_length`/`type_body_length` limits).
extension CodebaseDetailView {

    // MARK: - Not Indexed

    private func notIndexedSection(codebase: Codebase) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(.app("View.CodebaseDetailView.CodebaseHasNotBeen"))
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                reindexPhase = .loading(.app("View.CodebaseDetailView.Indexing"))
                Task {
                    await model.editing.reindex(codebaseID: codebase.id)
                    reindexPhase = .loaded
                }
            } label: {
                Label(.app("View.CodebaseDetailView.IndexNow"), systemImage: "arrow.clockwise")
            }
            .disabled(reindexPhase.isInFlight)
            AsyncOperationStatusView(identifierPrefix: "codebaseDetail.reindex", phase: reindexPhase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
