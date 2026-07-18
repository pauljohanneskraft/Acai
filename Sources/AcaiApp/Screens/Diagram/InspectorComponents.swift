import SwiftUI

/// A label/value row used in the package and call-graph metric sidebars.
struct MetricRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
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
