import SwiftUI

struct CardHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Rendered as the *intensity* of the card's family tint — a calm wash when healthy, a saturated
/// tile when critical — so hotspots pop out of the grid on their own.
enum MetricSeverity {
    case ok, caution, critical
}

/// Metrics with no meaningful "bad" direction have no threshold, and so sit at the calm baseline
/// intensity.
struct MetricThreshold {
    let amber: Double
    let red: Double

    func severity(for value: Double) -> MetricSeverity {
        if value >= red { return .critical }
        if value >= amber { return .caution }
        return .ok
    }
}

/// Shares one band hue per family so the statistics grid reads as coherent groups rather than a
/// rainbow; severity is conveyed separately via the tile's intensity (``MetricStatCard/fillOpacity``).
enum MetricFamily {
    case coupling, oo, smell, structural

    var color: Color {
        switch self {
        case .coupling:
            return .blue
        case .oo:
            return .green
        case .smell:
            return .yellow
        case .structural:
            return .red
        }
    }
}

struct MetricStatCard: View {
    let title: LocalizedStringResource
    let icon: String
    let color: Color
    let primary: LocalizedStringResource
    var secondary: LocalizedStringResource?
    var exemplar: LocalizedStringResource?
    var severity: MetricSeverity?
    var uniformHeight: CGFloat = 0
    /// Shown as a hover tooltip; reuses the same copy already shown in the tap-through drill-down.
    var blurb: LocalizedStringResource?
    var onTap: (() -> Void)?

    var body: some View {
        if let onTap {
            Button(action: onTap) { cardBody }
                .buttonStyle(.plain)
                .help(helpText)
        } else {
            cardBody
                .help(helpText)
        }
    }

    private var helpText: Text {
        blurb.map(Text.init) ?? Text(verbatim: "")
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3.bold())
                    .foregroundStyle(color)
                Text(localized: title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(localized: primary)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                if let secondary {
                    Text(localized: secondary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            if let exemplar {
                Text(localized: exemplar)
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
        .background(color.opacity(fillOpacity))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    private var fillOpacity: Double {
        switch severity {
        case .none, .some(.ok):
            return 0.12
        case .some(.caution):
            return 0.20
        case .some(.critical):
            return 0.30
        }
    }
}
