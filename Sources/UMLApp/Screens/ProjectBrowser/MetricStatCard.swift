import SwiftUI

/// Collects the tallest natural card height in a grid so every card can match it.
struct CardHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// A statistics card: an icon, a title, a primary value, and optional secondary text and an exemplar
/// caption (the item(s) driving the metric — up to three named, then "and N more"). When `onTap` is set
/// the whole card is a button (opens the metric's drill-down list). Reports its natural height and
/// stretches to `uniformHeight` so a row of cards shares one height. Knows nothing about the model.
struct MetricStatCard: View {
    let title: String
    let icon: String
    let color: Color
    let primary: String
    var secondary: String?
    var exemplar: String?
    var uniformHeight: CGFloat = 0
    var onTap: (() -> Void)?

    var body: some View {
        if let onTap {
            Button(action: onTap) { cardBody }
                .buttonStyle(.plain)
        } else {
            cardBody
        }
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3.bold())
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(primary)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                if let secondary {
                    Text(secondary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            if let exemplar {
                Text(exemplar)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: CardHeightPreferenceKey.self, value: proxy.size.height)
        })
        .frame(minHeight: uniformHeight > 0 ? uniformHeight : nil, alignment: .topLeading)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}
