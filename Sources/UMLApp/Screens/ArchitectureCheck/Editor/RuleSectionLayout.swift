import SwiftUI

/// A titled group of rule rows with an "add" button in its header. Shared chrome for every rule kind
/// so the individual editors only describe their rows.
struct RuleSection<Content: View>: View {
    let title: String
    let total: Int
    let onAdd: () -> Void
    @ViewBuilder let content: Content

    init(title: String, total: Int, onAdd: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.total = total
        self.onAdd = onAdd
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                if total > 0 {
                    Text("\(total)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onAdd) { Image(systemName: "plus.circle.fill") }
                    .buttonStyle(.plain)
                    .help("Add")
            }
            content
        }
        .padding(.vertical, 4)
    }
}

/// A single rule row rendered as a card with a remove button in the corner.
struct RuleCard<Content: View>: View {
    let onRemove: () -> Void
    @ViewBuilder let content: Content

    init(onRemove: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.onRemove = onRemove
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Remove")
            }
            content
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
