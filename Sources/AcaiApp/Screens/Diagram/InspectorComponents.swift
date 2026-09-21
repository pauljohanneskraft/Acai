import SwiftUI
import AcaiDiff
import AcaiRender

/// A selected element's comparison status (added/removed/changed), for diagram inspectors that
/// don't have `ClassDiagramInspector.whatChangedSection`'s per-member change detail — the coarser
/// counterpart, used by Call Graph, Package, Sequence and State diagrams.
struct ComparisonStatusRow: View {
    let status: DeltaStatus

    var body: some View {
        // `ViewThatFits` falls back to the stacked arrangement once the label and value no longer
        // fit beside the badge on one line — at the largest accessibility text sizes, in practice.
        ViewThatFits {
            HStack(spacing: 6) {
                DeltaBadgeView(status: status)
                Text(.app("View.ComparisonStatusRow.Comparison"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: status.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
            }
            HStack(alignment: .top, spacing: 6) {
                DeltaBadgeView(status: status)
                VStack(alignment: .leading, spacing: 2) {
                    Text(.app("View.ComparisonStatusRow.Comparison"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(verbatim: status.rawValue.capitalized)
                        .font(.caption.weight(.semibold))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("diagram.inspector.comparisonStatus")
    }
}

/// A label/value row used in the package and call-graph metric sidebars.
struct MetricRow: View {
    let label: LocalizedStringResource
    let value: String

    init(_ label: LocalizedStringResource, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        // See `ComparisonStatusRow` — same fallback to a stacked arrangement once the label and
        // value no longer both fit on one line.
        ViewThatFits {
            HStack {
                Text(localized: label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: value)
                    .font(.system(.caption, design: .monospaced))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(localized: label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: value)
                    .font(.system(.caption, design: .monospaced))
            }
        }
    }
}

extension View {
    /// The rounded card chrome shared by inspector cards, accent-highlighted when selected.
    func inspectorCard(highlighted: Bool) -> some View {
        padding(10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(highlighted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(highlighted ? Color.accentColor : .clear, lineWidth: 1)
            )
    }
}
