import SwiftUI

/// An empty state that names what is missing and offers the next action as a button, for the lists
/// and panes that would otherwise read as a bare "nothing here".
///
/// `children: .contain` keeps `actions`' own buttons queryable beside the container's identifier.
struct ActionableEmptyState<Actions: View>: View {
    let text: LocalizedStringResource
    let systemImage: String
    let identifier: String
    /// Fills its container on a pane; sized to its content inside a list row or a card.
    var fillsContainer = true
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: .spacingM) {
            Image(systemName: systemImage)
                .font(.system(size: fillsContainer ? 40 : 28))
                .foregroundStyle(.secondary)
            Text(localized: text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, .spacingXXL)
            actions()
                // Bordered and large gives the 44pt touch target; inside iPhone's `List` row a
                // default-styled button would make the whole row its hit area instead.
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: fillsContainer ? CGFloat.infinity : nil)
        .padding(.vertical, fillsContainer ? .zero : .spacingL)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

extension ActionableEmptyState where Actions == EmptyView {
    init(text: LocalizedStringResource, systemImage: String, identifier: String, fillsContainer: Bool = true) {
        self.init(
            text: text, systemImage: systemImage, identifier: identifier,
            fillsContainer: fillsContainer) { EmptyView() }
    }
}
