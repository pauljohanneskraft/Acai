import SwiftUI

/// A "N selected" list shared by every diagram type's Inspector tab: an icon+label(+detail) row
/// per selected item, optionally tappable to narrow the selection to just that item, plus an
/// optional bulk action applied to the whole selection.
struct MultiSelectionInspector<Item: Identifiable>: View where Item.ID == String {
    struct BulkAction {
        let label: LocalizedStringKey
        let systemImage: String
        let role: ButtonRole?
        let action: () -> Void
    }

    let items: [Item]
    /// The section header for the given selection count, e.g. an inflected "3 Methods Selected".
    let title: (Int) -> Text
    let rowIcon: (Item) -> String?
    let rowLabel: (Item) -> String
    let rowDetail: ((Item) -> String?)?
    /// Tapping a row narrows the selection to it; `nil` renders a non-interactive row.
    let onSelect: ((String) -> Void)?
    let bulkAction: BulkAction?

    var body: some View {
        List {
            Section {
                ForEach(items) { item in
                    row(for: item)
                }
            } header: {
                title(items.count)
            }
            if let bulkAction {
                Section {
                    Button(role: bulkAction.role) {
                        bulkAction.action()
                    } label: {
                        Label(bulkAction.label, systemImage: bulkAction.systemImage)
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("diagram.multiSelection.bulkAction")
                }
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func row(for item: Item) -> some View {
        if let onSelect {
            Button {
                onSelect(item.id)
            } label: {
                rowContent(item)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("diagram.multiSelection.row.\(item.id)")
        } else {
            rowContent(item)
        }
    }

    private func rowContent(_ item: Item) -> some View {
        HStack(spacing: 8) {
            if let systemImage = rowIcon(item) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }
            Text(verbatim: rowLabel(item))
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if let detail = rowDetail?(item) {
                Text(verbatim: detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}
