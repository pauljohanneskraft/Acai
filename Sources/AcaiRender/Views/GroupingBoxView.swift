import SwiftUI

/// Box drawn behind a group of type nodes that share the same grouping key (a directory
/// or a compiled product/module), echoing UML package notation.
public struct GroupingBoxView: View {
    let label: String

    public init(label: String) {
        self.label = label
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let cornerRadius: CGFloat = 10
    private let cornerPadding: CGFloat = 4
    /// `.caption`'s point size at the default `.large` category — matches the label's own font below
    /// so `tabHeight` and the text driving it never fall out of sync (see `tabHeight`'s doc comment).
    private var labelFontSize: CGFloat { 12 * dynamicTypeSize.scaleFactor }
    /// Derived from `labelFontSize` (rather than a fixed 22pt) so the tab always has room for its own
    /// text: a fixed height left the label overflowing its background and into the first child node's
    /// title bar once Dynamic Type grew the text past what 22pt could hold. The 22/12 ratio reproduces
    /// the original fixed height exactly at the default size.
    private var tabHeight: CGFloat { labelFontSize * (22.0 / 12.0) }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.accentColor.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1.5)
                )

            Text(label)
                .font(.system(size: labelFontSize, weight: .semibold))
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
