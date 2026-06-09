import SwiftUI

/// Box drawn behind a group of type nodes that share the same grouping key (a directory
/// or a compiled product/module). Rendered as a rounded rectangle with a small name tab
/// in the top-left corner, echoing UML package notation.
public struct GroupingBoxView: View {
    let label: String

    public init(label: String) {
        self.label = label
    }

    private let cornerRadius: CGFloat = 10
    private let cornerPadding: CGFloat = 4
    private let tabHeight: CGFloat = 22

    public var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.accentColor.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1.5)
                )

            Text(label)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: tabHeight)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: cornerRadius - cornerPadding,
                        bottomTrailingRadius: cornerRadius - cornerPadding
                    )
                    .fill(Color.accentColor.opacity(0.18))
                )
                .foregroundStyle(Color.accentColor)
                .padding(.leading, cornerPadding)
                .padding(.top, cornerPadding)
        }
        .allowsHitTesting(false)
    }
}
