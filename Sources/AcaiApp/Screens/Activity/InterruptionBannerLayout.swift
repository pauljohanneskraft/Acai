import SwiftUI

/// The frame both interruption banners share; the actions drop below the message once they don't fit beside it.
struct InterruptionBannerLayout<Message: View, Actions: View>: View {
    let systemImage: String
    @ViewBuilder let message: Message
    @ViewBuilder let actions: Actions

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                messageRow
                Spacer()
                actions
            }
            VStack(alignment: .leading, spacing: .spacingS) {
                messageRow
                HStack { actions }
            }
            VStack(alignment: .leading, spacing: .spacingS) {
                messageRow
                actions
            }
        }
        .padding(.spacingS)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }

    private var messageRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: systemImage)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: .spacingXXS) {
                message
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
