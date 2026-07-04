import SwiftUI

/// A foldable section of the codebase detail pane: a clickable headline header with a rotating
/// chevron and an optional trailing accessory, hiding its content when collapsed. Expansion state is
/// in-memory only (seeded from `defaultExpanded`), so it resets when the pane is rebuilt.
struct CollapsibleSection<Accessory: View, Content: View>: View {
    let title: String
    var defaultExpanded: Bool = true
    @ViewBuilder let accessory: () -> Accessory
    @ViewBuilder let content: () -> Content

    @State private var isExpanded: Bool

    init(
        title: String,
        defaultExpanded: Bool = true,
        @ViewBuilder accessory: @escaping () -> Accessory,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.defaultExpanded = defaultExpanded
        self.accessory = accessory
        self.content = content
        _isExpanded = State(initialValue: defaultExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text(title)
                        .font(.headline)
                    Spacer(minLength: 8)
                    accessory()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.top, 12)

            if isExpanded {
                content()
            }
        }
        .padding(.bottom, isExpanded ? 8 : 12)
    }
}

extension CollapsibleSection where Accessory == EmptyView {
    init(
        title: String,
        defaultExpanded: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(title: title, defaultExpanded: defaultExpanded, accessory: { EmptyView() }, content: content)
    }
}
