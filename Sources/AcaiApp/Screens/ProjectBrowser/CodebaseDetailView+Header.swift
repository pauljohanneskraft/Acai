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
        .task(id: freshnessRecheckTrigger) {
            await model.refreshFreshness(codebaseID: codebaseID)
        }
        .onAppear {
            freshnessRecheckTrigger += 1
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            freshnessRecheckTrigger += 1
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

                if codebase.managedCheckout != nil, let repository = codebase.repository {
                    Text(verbatim: "\(repository.remoteDisplayName) @ \(repository.ref)")
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
                if let revision = codebase.pinnedRevision {
                    pinnedRevisionCaption(revision: revision)
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
            if artifact != nil {
                queryButton(codebase: codebase)
                if codebase.guidedRoute != .offered {
                    guidedRouteButton(codebase: codebase)
                }
            }
            if codebase.managedCheckout != nil, let repository = codebase.repository {
                managedCheckoutActions(codebase: codebase, repository: repository)
            } else {
                localRevisionPicker(codebase: codebase)
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

    /// Opens `QueryView`, scoped to this codebase.
    private func queryButton(codebase: Codebase) -> some View {
        Button {
            model.selection = .query(codebase.id)
        } label: {
            Label(.app("View.CodebaseDetailView.Query"), systemImage: "magnifyingglass")
        }
        .accessibilityIdentifier("codebaseDetail.queryButton")
    }

    private func guidedRouteButton(codebase: Codebase) -> some View {
        Button {
            model.editing.setGuidedRoute(.offered, codebaseID: codebase.id)
        } label: {
            Label(.app("View.CodebaseDetailView.GuidedRoute"), systemImage: "map")
        }
        .accessibilityIdentifier("codebaseDetail.guidedRouteButton")
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
