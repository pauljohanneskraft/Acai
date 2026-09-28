import SwiftUI
import AcaiCore
import AcaiQuality
import AcaiLibrary

/// Queries one codebase's types and members by structural properties — backed by the same
/// `TypeQuery` the CLI's `inspect` command and the MCP server's inspect tool already run, so this
/// view can never disagree with what those report.
struct QueryView: View {
    let codebaseID: UUID

    @EnvironmentObject private var model: ProjectBrowserViewModel
    @State private var filter = QueryFilterState()
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
                Text(.app("View.QueryView.CodebaseNotFound"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("query.codebaseNotFoundState")
            }
        }
        .navigationTitle(.app("View.QueryView.Query"))
    }

    // MARK: - Not indexed

    private func notIndexedState(codebase: Codebase) -> some View {
        VStack(spacing: .spacingL) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(.app("View.QueryView.NotIndexedYet"))
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                reindexPhase = .loading(.app("View.QueryView.Indexing"))
                Task {
                    let outcome = await model.editing.reindex(codebaseID: codebase.id)
                    reindexPhase = AsyncOperationPhase(outcome, failure: .app("View.QueryView.IndexingFailed"))
                }
            } label: {
                Label(.app("View.QueryView.IndexNow"), systemImage: "arrow.clockwise")
            }
            .disabled(reindexPhase.isInFlight)
            .accessibilityIdentifier("query.indexNowButton")
            AsyncOperationStatusView(identifierPrefix: "query.reindex", phase: reindexPhase)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("query.notIndexedState")
    }

    // MARK: - Content

    private func content(codebase: Codebase, artifact: CodeArtifact) -> some View {
        let rows = TypeQuery(
            artifact: artifact, selector: filter.selector, members: filter.members,
            languageResolver: artifact.standardLanguageResolver
        ).rows
        return Group {
            if rows.isEmpty {
                emptyState(reason: filter.emptyStateReason(hasAnyType: !artifact.types.isEmpty))
            } else {
                List(rows, id: \.id) { row in
                    typeRow(row, codebase: codebase)
                        .listRowSeparator(.hidden)
                }
                .accessibilityIdentifier("query.list")
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
            Label(.app("View.QueryView.Filter"), systemImage: "line.3.horizontal.decrease.circle")
        }
        .accessibilityIdentifier("query.filterButton")
    }

    private var filterSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: .spacingL) {
                SelectorEditor(title: .app("View.QueryView.ShowOnly"), selector: $filter.selector)
                MemberFilterEditor(title: .app("View.QueryView.MemberFilter"), filter: $filter.members)
                if !filter.isEmpty {
                    Button(.app("View.QueryView.ClearFilters")) { filter.clear() }
                    .accessibilityIdentifier("query.clearFiltersButton")
                }
                Spacer()
            }
            .padding()
            #if os(macOS)
            .frame(minWidth: 420, minHeight: 480)
            #endif
            .navigationTitle(.app("View.QueryView.Filter"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(.app("View.QueryView.Done")) { showFilterSheet = false }
                        .keyboardShortcut(.confirmDialog)
                        .accessibilityIdentifier("query.filterSheetDoneButton")
                }
            }
        }
    }

    private func emptyState(reason: QueryFilterState.EmptyStateReason) -> some View {
        let text: LocalizedStringResource = reason == .codebaseHasNoTypes
            ? .app("View.QueryView.NoTypesInCodebase")
            : .app("View.QueryView.NoTypesMatchFilters")
        return VStack(spacing: .spacingM) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(localized: text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, .spacingXXL)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("query.emptyState")
    }

    // MARK: - Rows

    private func typeRow(_ row: TypeQuery.TypeRow, codebase: Codebase) -> some View {
        VStack(alignment: .leading, spacing: .spacingXS) {
            HStack(spacing: .spacingS) {
                Text(verbatim: row.kind.rawValue)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(verbatim: row.qualifiedName)
                    .fontWeight(.medium)
                Spacer()
                if !filter.members.hasActiveFacet {
                    Text(.app("View.QueryView.Members \(row.members.count)"))
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
            if filter.members.hasActiveFacet {
                memberRows(row, codebase: codebase)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, .spacingXS)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("query.row.\(row.id)")
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
        .accessibilityIdentifier("query.row.\(typeRow.id).member.\(member.name)")
    }
}

extension MemberFilter {
    /// Mirrors the internal `AcaiQuality.MemberFilter.isActive`; `TypeQuery` already drops types
    /// with no matching members once true, so `memberRows` is never called on an empty list.
    var hasActiveFacet: Bool {
        kind != nil || minParameters != nil || isPublicVar != nil || isOverride != nil
    }
}
