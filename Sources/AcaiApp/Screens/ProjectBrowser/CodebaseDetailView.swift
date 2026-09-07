import SwiftUI
import AcaiCore
import AcaiDiagram

struct CodebaseDetailView: View {
    let codebaseID: UUID
    private let repositoryService: GitHubRepositoryService
    @EnvironmentObject var model: ProjectBrowserViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var reindexPhase: AsyncOperationPhase = .idle
    @State private var pullPhase: AsyncOperationPhase = .idle
    @State private var refSwitchPhase: AsyncOperationPhase = .idle
    @State private var availableRefs: [GitHubRef] = []
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

    // MARK: - Header

    /// A single crowded row works on iPad/macOS, but on iPhone the title (icon + name + subtitle)
    /// and the actions (index status + branch picker/Pull, or Reindex) don't both fit — so compact
    /// width gets its own actions row underneath instead of squeezing everything into one line.
    private func headerSection(codebase: Codebase) -> some View {
        Group {
            if horizontalSizeClass == .compact {
                VStack(alignment: .leading, spacing: 12) {
                    headerTitleRow(codebase: codebase)
                    headerActionsRow(codebase: codebase)
                }
            } else {
                HStack {
                    headerTitleRow(codebase: codebase)
                    Spacer()
                    headerActionsRow(codebase: codebase)
                }
            }
        }
        .padding()
    }

    private func headerTitleRow(codebase: Codebase) -> some View {
        HStack {
            Image(systemName: "folder")
                .font(.title)
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                TextField(text: Binding(
                    get: { codebase.name },
                    set: { model.editing.updateCodebase(id: codebase.id, name: $0) }
                )) {
                    Text(.app("View.CodebaseDetailView.CodebaseName"))
                }
                .font(.title2.bold())
                .textFieldStyle(.plain)

                if let source = codebase.githubSource {
                    Text(verbatim: "\(source.owner)/\(source.repo) @ \(source.ref)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                } else {
                    Text(verbatim: (codebase.directoryPath as NSString).abbreviatingWithTildeInPath)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func headerActionsRow(codebase: Codebase) -> some View {
        HStack {
            indexStatus(codebase: codebase)
            if horizontalSizeClass == .compact {
                Spacer()
            }
            if let source = codebase.githubSource {
                githubActions(codebase: codebase, source: source)
            } else {
                Button {
                    reindexPhase = .loading(.app("View.CodebaseDetailView.Indexing"))
                    Task {
                        await model.editing.reindex(codebaseID: codebase.id)
                        reindexPhase = .loaded
                    }
                } label: {
                    Label(.app("View.CodebaseDetailView.Reindex"), systemImage: "arrow.clockwise")
                }
                .disabled(reindexPhase.isInFlight)
                .accessibilityIdentifier("codebaseDetail.reindexButton")
                AsyncOperationStatusView(identifierPrefix: "codebaseDetail.reindex", phase: reindexPhase)
            }
        }
    }

    @ViewBuilder
    private func githubActions(codebase: Codebase, source: GitHubSource) -> some View {
        Picker(.app("View.CodebaseDetailView.BranchTag"), selection: Binding(
            get: { GitHubRef(name: source.ref, kind: source.refKind).id },
            set: { newID in
                let currentRef = GitHubRef(name: source.ref, kind: source.refKind)
                guard let selected = (availableRefs + [currentRef]).first(where: { $0.id == newID }) else { return }
                refSwitchPhase = .loading(.app("View.CodebaseDetailView.SwitchingTo \(selected.name)"))
                Task {
                    await model.editing.switchGitHubRef(
                        codebaseID: codebase.id, ref: selected.name, kind: selected.kind)
                    refSwitchPhase = .loaded
                }
            }
        )) {
            if !availableRefs.contains(where: { $0.name == source.ref && $0.kind == source.refKind }) {
                Text(verbatim: source.ref).tag(GitHubRef(name: source.ref, kind: source.refKind).id)
            }
            ForEach(availableRefs) { ref in
                Text(verbatim: ref.name).tag(ref.id)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 160)
        .disabled(refSwitchPhase.isInFlight)
        .accessibilityIdentifier("codebaseDetail.refPicker")
        .task(id: codebase.id) { await loadAvailableRefs(source: source) }
        AsyncOperationStatusView(identifierPrefix: "codebaseDetail.refSwitch", phase: refSwitchPhase)

        Button {
            pullPhase = .loading(.app("View.CodebaseDetailView.Pulling"))
            Task {
                await model.editing.pull(codebaseID: codebase.id)
                pullPhase = .loaded
            }
        } label: {
            Label(.app("View.CodebaseDetailView.Pull"), systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(pullPhase.isInFlight)
        .accessibilityIdentifier("codebaseDetail.pullButton")
        AsyncOperationStatusView(identifierPrefix: "codebaseDetail.pull", phase: pullPhase)
    }

    private func loadAvailableRefs(source: GitHubSource) async {
        guard let account = GitHubTokenStore().load() else { return }
        availableRefs = (try? await repositoryService.refs(
            credential: account.credential, owner: source.owner, repo: source.repo)) ?? []
    }

    private func indexStatus(codebase: Codebase) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let date = codebase.lastIndexed {
                let formatted = date.formatted(date: .abbreviated, time: .shortened)
                Text(.app("View.CodebaseDetailView.LastIndexed \(formatted)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if codebase.hasParseErrors {
                Label(
                    .app("View.CodebaseDetailView.SyntaxIssues \(codebase.parseDiagnosticCount)"),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .help(.app("View.CodebaseDetailView.SomeFilesCouldNot"))
            }
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

// Not Indexed section — kept small; the diagram buttons/card-grid layout live in
// `CodebaseDetailView+Diagrams.swift` and the diagram configuration sheets live in
// `CodebaseDetailView+DiagramSheets.swift` (both separate files, kept there only to stay under
// this file's own `file_length` limit).
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
