import SwiftUI

struct ActionableEmptyState<Actions: View>: View {
    let text: LocalizedStringResource
    let systemImage: String
    let identifier: String
    /// Fills its container on a pane; sized to its content inside a list row or a card.
    let fillsContainer: Bool
    let actions: () -> Actions
    @ScaledMetric(relativeTo: .largeTitle) private var paneIconSize: CGFloat = 40
    @ScaledMetric(relativeTo: .title) private var rowIconSize: CGFloat = 28

    init(
        text: LocalizedStringResource, systemImage: String, identifier: String, fillsContainer: Bool = true,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.text = text
        self.systemImage = systemImage
        self.identifier = identifier
        self.fillsContainer = fillsContainer
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: .spacingM) {
            Image(systemName: systemImage)
                .font(.system(size: fillsContainer ? paneIconSize : rowIconSize))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(localized: text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, .spacingXXL)
            actions()
                // Bordered: a default-styled button in an iOS List row makes the whole row its hit area.
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
