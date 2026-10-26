import SwiftUI
import AcaiCore
import AcaiQuality
import AcaiLibrary

/// Queries one codebase's types and members by structural properties — backed by the same
/// `TypeQuery` the CLI's `inspect` command and the MCP server's inspect tool already run, so this
/// view can never disagree with what those report.
struct InspectView: View {
    let codebaseID: UUID

    @EnvironmentObject private var model: ProjectBrowserViewModel
    @State private var filter = InspectFilterState()
    @State private var reindexPhase: AsyncOperationPhase = .idle
    /// A sheet, not inline: stacking `SelectorEditor` and `MemberFilterEditor` inline squeezes the
    /// results list too short to render on a compact-height screen.
    @State private var showFilterSheet = false

    private var codebase: Codebase? {
        model.codebase(for: codebaseID)
    }

    private var artifact: CodeArtifact? {
        model.artifact(for: codebaseID)
    }

    var body: some View {
        Group {
            if let codebase {
                if let artifact {
                    content(codebase: codebase, artifact: artifact)
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) { filterButton }
                        }
                        .sheet(isPresented: $showFilterSheet) {
                            filterSheet
                        }
                } else {
                    notIndexedState(codebase: codebase)
                }
            } else {
                Text(.app("View.InspectView.CodebaseNotFound"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("inspect.codebaseNotFoundState")
            }
        }
        .navigationTitle(.app("View.InspectView.Inspect"))
    }

    // MARK: - Not indexed

    private func notIndexedState(codebase: Codebase) -> some View {
        VStack(spacing: .spacingL) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(.app("View.InspectView.NotIndexedYet"))
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                reindexPhase = .loading(.app("View.InspectView.Indexing"))
                Task {
                    let outcome = await model.editing.reindex(codebaseID: codebase.id)
                    reindexPhase = AsyncOperationPhase(outcome, failure: .app("View.InspectView.IndexingFailed"))
                }
            } label: {
                Label(.app("View.InspectView.IndexNow"), systemImage: "arrow.clockwise")
            }
            .disabled(reindexPhase.isInFlight)
            .accessibilityIdentifier("inspect.indexNowButton")
            AsyncOperationStatusView(identifierPrefix: "inspect.reindex", phase: reindexPhase)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("inspect.notIndexedState")
    }

    // MARK: - Content

    private func content(codebase: Codebase, artifact: CodeArtifact) -> some View {
        let rows = TypeQuery(
            artifact: artifact, selector: filter.selector, members: filter.members,
            languageResolver: artifact.standardLanguageResolver
        ).rows
        let names = artifact.typeDisplayNames
        return Group {
            if rows.isEmpty {
                emptyState(reason: filter.emptyStateReason(hasAnyType: !artifact.types.isEmpty))
            } else {
                List(rows, id: \.id) { row in
                    typeRow(row, displayName: names.name(forID: row.id), codebase: codebase)
                        .listRowSeparator(.hidden)
                }
                .accessibilityIdentifier("inspect.list")
                #if os(iOS)
                .listStyle(.plain)
                #endif
            }
        }
    }

    private var filterButton: some View {
        Button {
            showFilterSheet = true
        } label: {
            Label(.app("View.InspectView.Filter"), systemImage: "line.3.horizontal.decrease.circle")
        }
        .accessibilityIdentifier("inspect.filterButton")
    }

    private var filterSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: .spacingL) {
                SelectorEditor(title: .app("View.InspectView.ShowOnly"), selector: $filter.selector)
                MemberFilterEditor(title: .app("View.InspectView.MemberFilter"), filter: $filter.members)
                if !filter.isEmpty {
                    Button(.app("View.InspectView.ClearFilters")) { filter.clear() }
                    .accessibilityIdentifier("inspect.clearFiltersButton")
                }
                Spacer()
            }
            .padding()
            #if os(macOS)
            .frame(minWidth: 420, minHeight: 480)
            #endif
            .navigationTitle(.app("View.InspectView.Filter"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(.app("View.InspectView.Done")) { showFilterSheet = false }
                        .keyboardShortcut(.confirmDialog)
                        .accessibilityIdentifier("inspect.filterSheetDoneButton")
                }
            }
        }
    }

    /// Only the filtered case has a next action — when the codebase itself has no types, clearing
    /// the filters would leave the list just as empty.
    @ViewBuilder
    private func emptyState(reason: InspectFilterState.EmptyStateReason) -> some View {
        if reason == .codebaseHasNoTypes {
            ActionableEmptyState(
                text: .app("View.InspectView.NoTypesInCodebase"),
                systemImage: "magnifyingglass",
                identifier: "inspect.emptyState"
            )
        } else {
            ActionableEmptyState(
                text: .app("View.InspectView.NoTypesMatchFilters"),
                systemImage: "line.3.horizontal.decrease.circle",
                identifier: "inspect.emptyState"
            ) {
                Button {
                    filter.clear()
                } label: {
                    Label(
                        .app("View.InspectView.ClearFilters"),
                        systemImage: "line.3.horizontal.decrease.circle")
                }
                .accessibilityIdentifier("inspect.emptyState.clearFiltersButton")
            }
        }
    }

    // MARK: - Rows

    private func typeRow(_ row: TypeQuery.TypeRow, displayName: String, codebase: Codebase) -> some View {
        VStack(alignment: .leading, spacing: .spacingXS) {
            HStack(spacing: .spacingS) {
                Text(verbatim: row.kind.rawValue)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(verbatim: displayName)
                    .fontWeight(.medium)
                Spacer()
                if !filter.members.hasActiveFacet {
                    Text(.app("View.InspectView.Members \(row.members.count)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(verbatim: row.access.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, .spacingXS)
                    .padding(.vertical, .spacingXXS)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .contentShape(Rectangle())
            .openInCodeElement(.type(id: row.id), codebase: codebase, relativePath: row.location?.filePath)
            if let location = row.location {
                locationRow(location, codebase: codebase)
            }
            if let documentation = row.documentation {
                Text(verbatim: documentation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("inspect.row.\(row.id).documentation")
            }
            if filter.members.hasActiveFacet {
                memberRows(row, codebase: codebase)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, .spacingXS)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inspect.row.\(row.id)")
    }

    private func locationRow(_ location: SourceLocation, codebase: Codebase) -> some View {
        HStack(spacing: .spacingS) {
            Text(verbatim: "\(location.filePath):\(location.line)")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            ViewSourceButton(codebase: codebase, relativePath: location.filePath)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private func memberRows(_ row: TypeQuery.TypeRow, codebase: Codebase) -> some View {
        VStack(alignment: .leading, spacing: .spacingXXS) {
            ForEach(Array(row.members.enumerated()), id: \.offset) { _, member in
                memberRow(member, typeRow: row, codebase: codebase)
            }
        }
        .padding(.leading, .spacingL)
    }

    private func memberRow(_ member: TypeQuery.MemberRow, typeRow: TypeQuery.TypeRow, codebase: Codebase) -> some View {
        HStack(spacing: .spacingXS) {
            Text(verbatim: member.kind.rawValue)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(verbatim: member.name)
                .font(.callout)
            if member.parameterCount > 0 {
                Text(verbatim: "(\(member.parameterCount))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(verbatim: member.access.rawValue)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .openInCodeElement(
            .method(typeName: typeRow.qualifiedName, methodName: member.name),
            codebase: codebase, relativePath: member.location?.filePath)
        .accessibilityIdentifier("inspect.row.\(typeRow.id).member.\(member.name)")
    }
}

extension MemberFilter {
    /// Mirrors the internal `AcaiQuality.MemberFilter.isActive`; `TypeQuery` already drops types
    /// with no matching members once true, so `memberRows` is never called on an empty list.
    var hasActiveFacet: Bool {
        kind != nil || minParameters != nil || isPublicVar != nil || isOverride != nil
    }
}
