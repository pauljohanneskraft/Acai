import SwiftUI

/// Expansion state is in-memory only (seeded from `defaultExpanded`), so it resets when the pane
/// is rebuilt.
struct CollapsibleSection<Accessory: View, Content: View>: View {
    let title: LocalizedStringResource
    var defaultExpanded: Bool = true
    @ViewBuilder let accessory: () -> Accessory
    @ViewBuilder let content: () -> Content

    @State private var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: LocalizedStringResource,
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
        VStack(alignment: .leading, spacing: Spacing.s) {
            Button {
                withAnimation(Animation.disclosure.respecting(reduceMotion: reduceMotion)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: Spacing.s) {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text(localized: title)
                        .font(.headline)
                    Spacer(minLength: 8)
                    accessory()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.top, Spacing.m)

            if isExpanded {
                content()
            }
        }
        .padding(.bottom, isExpanded ? Spacing.s : Spacing.m)
    }
}

extension CollapsibleSection where Accessory == EmptyView {
    init(
        title: LocalizedStringResource,
        defaultExpanded: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(title: title, defaultExpanded: defaultExpanded, accessory: { EmptyView() }, content: content)
    }
}
