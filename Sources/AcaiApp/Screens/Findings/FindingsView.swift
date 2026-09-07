import SwiftUI

/// The project-level Findings view: every quality violation, dead-code candidate, and
/// health-check parse diagnostic across every codebase in the project, aggregated into one
/// sortable (severity first, then recency), filterable (kind, codebase) list.
///
/// Every row is a `CodeElementReference`, so it gets the full "Open in…"/View Source treatment
/// for free, plus a "Suppress" action writing to a project-level baseline file.
struct FindingsView: View {
    let projectID: UUID

    @EnvironmentObject private var model: ProjectBrowserViewModel

    @State private var selectedKinds: Set<Finding.Kind> = Set(Finding.Kind.allCases)
    @State private var selectedCodebaseID: UUID?
    @State private var showSuppressed = false
    @State private var suppression = FindingsSuppressionBaseline()
    @State private var isLoadingSuppression = true
    @State private var suppressionError: String?
    @State private var suppressionSavePhase: AsyncOperationPhase = .idle

    private var project: Project? {
        model.store.projects.first { $0.id == projectID }
    }

    var body: some View {
        Group {
            if let project {
                content(project: project)
            } else {
                Text(.app("View.FindingsView.ProjectNotFound"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("findings.projectNotFoundState")
            }
        }
        .navigationTitle(.app("View.FindingsView.Findings"))
        .task(id: projectID) {
            await loadSuppression()
        }
        .task(id: projectID) {
            requestAnalyses()
        }
        .alert(
            .app("View.FindingsView.CouldNotSaveSuppression"),
            isPresented: Binding(get: { suppressionError != nil }, set: { if !$0 { suppressionError = nil } })
        ) {
            Button(.app("View.FindingsView.OK"), role: .cancel) { suppressionError = nil }
        } message: {
            Text(verbatim: suppressionError ?? "")
        }
    }

    @ViewBuilder
    private func content(project: Project) -> some View {
        if project.codebases.isEmpty {
            emptyState(
                text: .app("View.FindingsView.NoCodebasesYet"),
                identifier: "findings.noCodebasesState")
        } else {
            let aggregator = FindingsAggregator(project: project, model: model)
            let notIndexed = aggregator.codebasesNotIndexed()
            if notIndexed.count == project.codebases.count {
                emptyState(
                    text: .app("View.FindingsView.NoCodebaseIndexedYet"),
                    identifier: "findings.notIndexedState")
            } else {
                let allFindings = aggregator.findings()
                let stillAnalyzing = aggregator.codebasesStillAnalyzing()
                if allFindings.isEmpty && !stillAnalyzing.isEmpty {
                    loadingState(count: stillAnalyzing.count)
                } else {
                    listContent(
                        project: project, allFindings: allFindings,
                        stillAnalyzing: stillAnalyzing, notIndexed: notIndexed)
                }
            }
        }
    }

    private func emptyState(text: LocalizedStringResource, identifier: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(localized: text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(identifier)
    }

    private func loadingState(count: Int) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(.app("View.FindingsView.AnalyzingCodebaseS \(count)"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("findings.loadingState")
    }

    // MARK: - List + filters

    @ViewBuilder
    private func listContent(
        project: Project, allFindings: [Finding], stillAnalyzing: [Codebase], notIndexed: [Codebase]
    ) -> some View {
        let visible = filteredAndSorted(allFindings)
        VStack(alignment: .leading, spacing: 0) {
            filterBar(project: project)
            AsyncOperationStatusView(identifierPrefix: "findings.suppressionSave", phase: suppressionSavePhase)
            if !stillAnalyzing.isEmpty || !notIndexed.isEmpty {
                statusNote(stillAnalyzing: stillAnalyzing, notIndexed: notIndexed)
            }
            Divider()
            if visible.isEmpty {
                emptyState(
                    text: allFindings.isEmpty
                        ? .app("View.FindingsView.NoFindingsClean")
                        : .app("View.FindingsView.NoFindingsMatchFilters"),
                    identifier: "findings.emptyState")
            } else {
                List(visible) { finding in
                    FindingRow(
                        finding: finding,
                        codebase: model.codebase(for: finding.codebaseID),
                        isSuppressed: suppression.suppressedFindingIDs.contains(finding.id),
                        // `nil` while the baseline is still loading — hides the action rather than
                        // risking a suppress/un-suppress tap racing the in-flight load and having
                        // its result silently overwritten once that load completes.
                        onToggleSuppressed: isLoadingSuppression ? nil : { toggleSuppressed(finding) }
                    )
                    .listRowSeparator(.hidden)
                }
                .accessibilityIdentifier("findings.list")
                #if os(iOS)
                .listStyle(.plain)
                #endif
            }
        }
    }

    private func statusNote(stillAnalyzing: [Codebase], notIndexed: [Codebase]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !stillAnalyzing.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(.app("View.FindingsView.StillAnalyzingMoreCodebase \(stillAnalyzing.count)"))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if !notIndexed.isEmpty {
                Text(.app("View.FindingsView.CodebaseSNotIndexed \(notIndexed.count)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private func filterBar(project: Project) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Finding.Kind.allCases) { kind in
                        kindChip(kind)
                    }
                }
            }
            HStack {
                Picker(.app("View.FindingsView.Codebase"), selection: $selectedCodebaseID) {
                    Text(.app("View.FindingsView.AllCodebases")).tag(UUID?.none)
                    ForEach(project.codebases.sorted { $0.name < $1.name }) { codebase in
                        Text(verbatim: codebase.name).tag(Optional(codebase.id))
                    }
                }
                .accessibilityIdentifier("findings.codebaseFilter")
                Spacer()
                Toggle(.app("View.FindingsView.ShowSuppressedToo"), isOn: $showSuppressed)
                    .toggleStyle(.button)
                    .accessibilityIdentifier("findings.showSuppressedToggle")
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func kindChip(_ kind: Finding.Kind) -> some View {
        let isSelected = selectedKinds.contains(kind)
        return Button {
            if isSelected {
                selectedKinds.remove(kind)
            } else {
                selectedKinds.insert(kind)
            }
        } label: {
            Label(kind.title, systemImage: kind.systemImage)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("findings.kindFilter.\(kind.rawValue)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func filteredAndSorted(_ findings: [Finding]) -> [Finding] {
        findings
            .filter { selectedKinds.contains($0.kind) }
            .filter { selectedCodebaseID == nil || $0.codebaseID == selectedCodebaseID }
            .filter { showSuppressed || !suppression.suppressedFindingIDs.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
                let leftDate = lhs.indexedAt ?? .distantPast
                let rightDate = rhs.indexedAt ?? .distantPast
                if leftDate != rightDate { return leftDate > rightDate }
                return lhs.id < rhs.id
            }
    }

    // MARK: - Loading analyses / suppression

    /// `ProjectBrowserViewModel.analyses` is `@Published`, so the view refreshes progressively as
    /// each codebase's analysis completes rather than blocking on all of them together.
    private func requestAnalyses() {
        guard let project else { return }
        for codebase in project.codebases {
            Task { await model.ensureAnalysisLoaded(codebaseID: codebase.id) }
        }
    }

    private func loadSuppression() async {
        isLoadingSuppression = true
        let baseDir = model.store.baseDir
        let projectID = projectID
        suppression = await Task.detached(priority: .userInitiated) {
            FindingsSuppressionStore(baseDir: baseDir).load(projectID: projectID)
        }.value
        isLoadingSuppression = false
    }

    private func toggleSuppressed(_ finding: Finding) {
        var updated = suppression
        if updated.suppressedFindingIDs.contains(finding.id) {
            updated.suppressedFindingIDs.remove(finding.id)
        } else {
            updated.suppressedFindingIDs.insert(finding.id)
        }
        suppression = updated  // optimistic: the row's state flips immediately
        let baseDir = model.store.baseDir
        let projectID = projectID
        // A fresh `let` (not the `var` mutated above) so this Sendable value crosses the isolation
        // boundary as an immutable copy, not a captured mutable variable — the same rebinding
        // `ViewSourceButton.resolve()` uses for its own detached-task capture.
        let toSave = updated
        suppressionSavePhase = .loading(.app("View.FindingsView.Saving"))
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try FindingsSuppressionStore(baseDir: baseDir).save(toSave, projectID: projectID)
                }.value
                suppressionSavePhase = .loaded
            } catch {
                suppressionError = error.localizedDescription
                suppressionSavePhase = .failed(error.localizedDescription)
            }
        }
    }
}
