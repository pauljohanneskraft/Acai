import SwiftUI

/// A ranked drill-down for one statistics card: the items behind the metric, sorted by it. Each row
/// can reveal its item in Finder (a type's file, or a module's directory). Built by the section, which
/// owns the artifact/codebase needed for the reveal actions.
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
    }
}

/// Presents a `StatisticDetail` as a sortable, revealable list.
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
                HStack(spacing: 8) {
                    Text(row.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(row.value)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .revealsInFinder(codebase: codebase, relativePath: row.relativePath)
            }
        }
    }
}
