import SwiftUI

/// Collects the tallest natural card height in a grid so every card can match it.
struct CardHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// How serious a metric's headline value is. Rendered as the *intensity* of the card's family tint —
/// a calm wash when healthy, a saturated tile when critical — so the hotspots pop out of the grid on
/// their own. The card owns the opacity ramp (``MetricStatCard/fillOpacity``).
enum MetricSeverity {
    case ok, caution, critical
}

/// The amber/red guardrails for a directional metric — the value where it turns from healthy to a
/// caution, then to a critical hotspot. Metrics with no meaningful "bad" direction have no threshold
/// (and so sit at the calm baseline intensity).
struct MetricThreshold {
    let amber: Double
    let red: Double

    func severity(for value: Double) -> MetricSeverity {
        if value >= red { return .critical }
        if value >= amber { return .caution }
        return .ok
    }
}

/// A family of related metrics, sharing one band hue so the statistics grid reads as coherent groups
/// rather than a rainbow. Four vivid, diverse tones drawn from the original card palette — spread
/// around the wheel (a warm one included) so the grid stays colourful. Severity lives in the tile's
/// intensity (see ``MetricStatCard/fillOpacity``), kept subtle so the hues never muddy.
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
    /// Traffic-light standing for the headline value; `nil` for metrics with no "bad" direction.
    var severity: MetricSeverity?
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
        .background(color.opacity(fillOpacity))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    /// The family tint's opacity, ramped by severity so hotspots read as the boldest tiles: a calm wash
    /// for healthy and direction-neutral metrics (`nil`), stronger for a caution, boldest for a critical.
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
