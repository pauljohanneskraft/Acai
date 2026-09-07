import SwiftUI

struct StatisticDetail: Identifiable {
    let id = UUID()
    let title: LocalizedStringResource
    let description: LocalizedStringResource?
    let rows: [Row]

    struct Row: Identifiable {
        let id: String
        let name: String
        let value: String
        let relativePath: String?
        let reference: CodeElementReference
    }
}

struct StatisticDetailSheet: View {
    let codebase: Codebase
    let detail: StatisticDetail
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let description = detail.description {
                    Text(localized: description)
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
            .navigationTitle(Text(localized: detail.title))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(.app("View.StatisticDetailSheet.Done")) { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if detail.rows.isEmpty {
            Text(.app("View.StatisticDetailSheet.NothingShow"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(detail.rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(verbatim: row.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(verbatim: row.value)
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
