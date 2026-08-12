import SwiftUI

/// A ranked drill-down for one statistics card: the items behind the metric, sorted by it. Each row
/// offers the full "Open in…" resolution plus "View Source" (Finder reveal kept as an
/// additional macOS-only secondary action). Built by the section, which owns the artifact/codebase
/// needed for these actions.
struct StatisticDetail: Identifiable {
    let id = UUID()
    let title: String
    /// One- or two-sentence explanation of the metric and how to read it (good vs. smell).
    let description: String
    let rows: [Row]

    struct Row: Identifiable {
        /// A type id or module name — stable within one list.
        let id: String
        let name: String
        let value: String
        /// The item's path relative to the codebase directory, or `nil` when it can't be resolved.
        let relativePath: String?
        /// The element this row is about — a type or a module, matching how the section built
        /// this row (`typeDetail`/`moduleDetail`).
        let reference: CodeElementReference
    }
}

/// Presents a `StatisticDetail` as a sortable, actionable list.
struct StatisticDetailSheet: View {
    let codebase: Codebase
    let detail: StatisticDetail
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !detail.description.isEmpty {
                    Text(detail.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                    Divider()
                }
                content
            }
            #if os(macOS)
            .frame(maxWidth: 480, minHeight: 420)
            #endif
            .navigationTitle(detail.title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if detail.rows.isEmpty {
            Text("Nothing to show.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(detail.rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(row.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(row.value)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .openInCodeElement(row.reference, codebase: codebase, relativePath: row.relativePath)
                    // Only for a type row: a module row's `relativePath` is a directory, not a
                    // file, and Quick Look isn't a useful way to "view source" for one.
                    if case .type = row.reference, let relativePath = row.relativePath {
                        ViewSourceButton(codebase: codebase, relativePath: relativePath)
                    }
                }
            }
        }
    }
}
