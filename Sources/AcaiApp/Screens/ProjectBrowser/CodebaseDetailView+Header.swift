import SwiftUI

extension CodebaseDetailView {

    // MARK: - Header

    /// A single crowded row works on iPad/macOS, but on iPhone the title (icon + name + subtitle)
    /// and the actions (index status + branch picker/Pull, or Reindex) don't both fit — so compact
    /// width gets its own actions row underneath instead of squeezing everything into one line.
    func headerSection(codebase: Codebase) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
            if model.freshness(for: codebaseID) == .stale {
                staleBanner(codebase: codebase)
            }
        }
        .padding()
        .task(id: FreshnessCheckToken(codebaseID: codebaseID, lastIndexed: codebase.lastIndexed)) {
            await model.ensureFreshnessLoaded(codebaseID: codebaseID)
        }
        // The code can change on disk without anything in-app noticing — most commonly, the user
        // switches away (to an external editor, or another codebase and back) and back. Re-check
        // whenever this becomes visible again, or the app regains focus — not just when a reindex
        // moves the stored baseline.
        .onAppear {
            Task { await model.refreshFreshness(codebaseID: codebaseID) }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await model.refreshFreshness(codebaseID: codebaseID) }
        }
    }

    private struct FreshnessCheckToken: Equatable {
        let codebaseID: UUID
        let lastIndexed: Date?
    }

    private func staleBanner(codebase: Codebase) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(.app("View.CodebaseDetailView.AnalysisOutOfDate"), systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)
            Spacer()
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
            .accessibilityIdentifier("codebaseDetail.staleBanner.reindexButton")
            AsyncOperationStatusView(identifierPrefix: "codebaseDetail.staleBanner.reindex", phase: reindexPhase)
        }
        .padding(8)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("codebaseDetail.staleBanner")
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
}
