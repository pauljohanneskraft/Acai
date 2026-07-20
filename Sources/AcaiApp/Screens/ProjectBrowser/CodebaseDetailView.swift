import SwiftUI
import AcaiCore
import AcaiDiagram

/// Main content area view displayed when a codebase is selected in the sidebar.
/// Shows statistics, types, relationships, and diagram generation buttons.
struct CodebaseDetailView: View {
    let codebaseID: UUID
    @EnvironmentObject private var model: ProjectBrowserViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isIndexing = false
    /// `true` while a GitHub `Pull` or branch/tag switch is in flight — mirrors `isIndexing`'s
    /// role for the local-folder "Reindex" action.
    @State private var isPulling = false
    /// Branches + tags for a GitHub-backed codebase's ref picker, loaded once per codebase.
    @State private var availableRefs: [GitHubRef] = []
    /// Set when the user clicks "Sequence Diagram"; drives the configuration popup.
    @State private var sequenceConfigContext: ConfigContext?
    /// Set when the user clicks "State Diagram"; drives the variable-selection popup.
    @State private var stateConfigContext: ConfigContext?
    /// Set when the user clicks "Call Graph"; drives the scope-selection popup.
    @State private var callGraphConfigContext: ConfigContext?
    /// The detail pane's current content width, used to lay out the diagram/statistics card grids so
    /// they fill the full width and wrap to more rows only when space runs out.
    @State private var contentWidth: CGFloat = 0
    /// The ranked drill-down presented when a statistics card is tapped.
    @State var statisticDetail: StatisticDetail?
    /// Uniform card heights per grid (each = the tallest card in that grid), so cards never differ.
    @State var statCardHeight: CGFloat = 0
    @State private var diagramCardHeight: CGFloat = 0

    /// Identifies the codebase a pending diagram configuration belongs to.
    private struct ConfigContext: Identifiable {
        let projectID: UUID
        let codebaseID: UUID
        var id: UUID { codebaseID }
    }

    var codebase: Codebase? {
        model.codebase(for: codebaseID)
    }

    var artifact: CodeArtifact? {
        model.artifact(for: codebaseID)
    }

    private var projectID: UUID? {
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
                        CodebaseRelationshipsSection(artifact: artifact)
                    } else {
                        notIndexedSection(codebase: codebase)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
            }
            .navigationTitle(codebase.name)
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
            }
        } else {
            Text("Codebase not found")
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
                TextField("Codebase Name", text: Binding(
                    get: { codebase.name },
                    set: { model.editing.updateCodebase(id: codebase.id, name: $0) }
                ))
                .font(.title2.bold())
                .textFieldStyle(.plain)

                if let source = codebase.githubSource {
                    Text("\(source.owner)/\(source.repo) @ \(source.ref)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                } else {
                    Text((codebase.directoryPath as NSString).abbreviatingWithTildeInPath)
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
                    isIndexing = true
                    Task {
                        await model.editing.reindex(codebaseID: codebase.id)
                        isIndexing = false
                    }
                } label: {
                    Label("Reindex", systemImage: "arrow.clockwise")
                }
                .disabled(isIndexing)
            }
        }
    }

    /// The "Pull" + branch/tag picker shown instead of "Reindex" for a GitHub-backed codebase.
    @ViewBuilder
    private func githubActions(codebase: Codebase, source: GitHubSource) -> some View {
        Picker("Branch/Tag", selection: Binding(
            get: { GitHubRef(name: source.ref, kind: source.refKind).id },
            set: { newID in
                let currentRef = GitHubRef(name: source.ref, kind: source.refKind)
                guard let selected = (availableRefs + [currentRef]).first(where: { $0.id == newID }) else { return }
                isPulling = true
                Task {
                    await model.editing.switchGitHubRef(
                        codebaseID: codebase.id, ref: selected.name, kind: selected.kind)
                    isPulling = false
                }
            }
        )) {
            if !availableRefs.contains(where: { $0.name == source.ref && $0.kind == source.refKind }) {
                Text(source.ref).tag(GitHubRef(name: source.ref, kind: source.refKind).id)
            }
            ForEach(availableRefs) { ref in
                Text(ref.name).tag(ref.id)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 160)
        .disabled(isPulling)
        .task(id: codebase.id) { await loadAvailableRefs(source: source) }

        Button {
            isPulling = true
            Task {
                await model.editing.pull(codebaseID: codebase.id)
                isPulling = false
            }
        } label: {
            Label("Pull", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(isPulling)
    }

    private func loadAvailableRefs(source: GitHubSource) async {
        guard let account = GitHubTokenStore().load() else { return }
        let client = GitHubAPIClient(credential: account.credential)
        async let branches = client.branches(owner: source.owner, repo: source.repo)
        async let tags = client.tags(owner: source.owner, repo: source.repo)
        availableRefs = (try? await branches + tags) ?? []
    }

    private func indexStatus(codebase: Codebase) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let date = codebase.lastIndexed {
                Text("Last indexed: \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if codebase.hasParseErrors {
                Label(
                    "\(codebase.parseDiagnosticCount) syntax issue(s) detected",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .help("Some files could not be fully parsed; the diagram may be incomplete.")
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
        DeadCodeSection(codebase: codebase, report: analysis.deadCode)
        Divider()
        ParseHealthSection(codebase: codebase, report: analysis.health)
        Divider()
    }

    /// Shown while the codebase's analysis is being computed on a background thread, so selecting a
    /// codebase never blocks on the scans.
    private var analyzingPlaceholder: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Analyzing codebase…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 28)
    }

}

// Statistics, diagram buttons, and their layout helpers — kept in an extension so the main type body
// stays within SwiftLint's `type_body_length`.
extension CodebaseDetailView {

    // MARK: - Card grid layout

    /// Flexible columns sized so `count` cards fill the full content width, wrapping to more rows only
    /// when the pane is too narrow to fit them all at `target` width. Capping the column count at the
    /// card count (rather than `.adaptive`) keeps the row full-width instead of leaving empty trailing
    /// columns when there are fewer cards than would fit.
    func cardColumns(count: Int, target: CGFloat = 200) -> [GridItem] {
        let usableWidth = contentWidth - 32  // outer .padding(.horizontal) on each side
        let fitting = max(1, Int((usableWidth + 12) / (target + 12)))
        let columns = max(1, min(count, fitting))
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: columns)
    }

    // MARK: - Diagrams

    /// The diagram-generation buttons, shown inline directly under the header (no fold, no title) since
    /// they are the pane's primary action.
    private func diagramsBar(codebase: Codebase, artifact: CodeArtifact) -> some View {
        LazyVGrid(columns: cardColumns(count: DiagramType.allCases.count), spacing: 12) {
            ForEach(DiagramType.allCases) { type in
                diagramButton(codebase: codebase, type: type)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
        .onPreferenceChange(CardHeightPreferenceKey.self) { height in
            if abs(diagramCardHeight - height) > 0.5 { diagramCardHeight = height }
        }
    }

    /// A diagram type button. Each click creates a new generated diagram of that type; sequence
    /// and state diagrams first open their configuration popup (entry point / variable selection).
    private func diagramButton(codebase: Codebase, type: DiagramType) -> some View {
        Button {
            guard let projectID else { return }
            if type == .sequenceDiagram {
                sequenceConfigContext = ConfigContext(projectID: projectID, codebaseID: codebase.id)
                return
            }
            if type == .stateDiagram {
                stateConfigContext = ConfigContext(projectID: projectID, codebaseID: codebase.id)
                return
            }
            if type == .callGraph {
                callGraphConfigContext = ConfigContext(projectID: projectID, codebaseID: codebase.id)
                return
            }
            if let id = model.diagrams.add(
                to: projectID,
                codebaseID: codebase.id,
                content: GeneratedDiagram.Content(type: type)
            ) {
                model.selection = .generatedDiagram(id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: type.systemImage)
                    .font(.title2.bold())
                Text(type.displayName)
                    .font(.title3.bold())
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: CardHeightPreferenceKey.self, value: proxy.size.height)
            })
            .frame(minHeight: diagramCardHeight > 0 ? diagramCardHeight : nil, alignment: .topLeading)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Not Indexed

    private func notIndexedSection(codebase: Codebase) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("This codebase has not been indexed yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                isIndexing = true
                Task {
                    await model.editing.reindex(codebaseID: codebase.id)
                    isIndexing = false
                }
            } label: {
                Label("Index Now", systemImage: "arrow.clockwise")
            }
            .disabled(isIndexing)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Diagram configuration sheets

extension CodebaseDetailView {

    /// The state-diagram configuration popup, presented when "State Diagram" is clicked.
    @ViewBuilder
    private func stateConfigSheet(for context: ConfigContext) -> some View {
        if let artifact = model.artifact(for: context.codebaseID) {
            StateConfigSheet(
                artifact: artifact,
                onCancel: { stateConfigContext = nil },
                onCreate: { config in
                    if let id = model.diagrams.add(
                        to: context.projectID,
                        codebaseID: context.codebaseID,
                        content: .stateDiagram(config)
                    ) {
                        model.selection = .generatedDiagram(id)
                    }
                    stateConfigContext = nil
                }
            )
        }
    }

    /// The call-graph scope popup, presented when "Call Graph" is clicked.
    @ViewBuilder
    private func callGraphConfigSheet(for context: ConfigContext) -> some View {
        if let artifact = model.artifact(for: context.codebaseID) {
            CallGraphConfigSheet(
                artifact: artifact,
                onCancel: { callGraphConfigContext = nil },
                onCreate: { scope in
                    if let id = model.diagrams.add(
                        to: context.projectID,
                        codebaseID: context.codebaseID,
                        content: .callGraph(scope)
                    ) {
                        model.selection = .generatedDiagram(id)
                    }
                    callGraphConfigContext = nil
                }
            )
        }
    }

    /// The sequence-diagram configuration popup, presented when "Sequence Diagram" is clicked.
    @ViewBuilder
    private func sequenceConfigSheet(for context: ConfigContext) -> some View {
        if let artifact = model.artifact(for: context.codebaseID) {
            SequenceConfigSheet(
                artifact: artifact,
                onCancel: { sequenceConfigContext = nil },
                onCreate: { config in
                    if let id = model.diagrams.add(
                        to: context.projectID,
                        codebaseID: context.codebaseID,
                        content: .sequenceDiagram(config)
                    ) {
                        model.selection = .generatedDiagram(id)
                    }
                    sequenceConfigContext = nil
                }
            )
        }
    }
}
