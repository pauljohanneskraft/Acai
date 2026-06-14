import SwiftUI
import UMLDiagram

/// The package diagram's metrics sidebar. The canvas stays label-free (UML package shapes +
/// thickness-weighted dependency arrows); every number — instability, abstractness, afferent/
/// efferent coupling, type count, distance from the main sequence — is shown here instead.
struct PackageDiagramInspector: View {
    let diagram: PackageDependencyDiagram
    let selectedNodeIDs: Set<String>

    /// Selected modules first (in selection-agnostic name order), then the rest.
    private var orderedNodes: [PackageDependencyDiagram.Node] {
        let sorted = diagram.nodes.sorted { $0.name < $1.name }
        let selected = sorted.filter { selectedNodeIDs.contains($0.id) }
        let rest = sorted.filter { !selectedNodeIDs.contains($0.id) }
        return selected + rest
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Modules")
                    .font(.headline)
                ForEach(orderedNodes, id: \.id) { node in
                    moduleCard(node, highlighted: selectedNodeIDs.contains(node.id))
                }
                legend
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func moduleCard(_ node: PackageDependencyDiagram.Node, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: node.zoneColorHex))
                    .frame(width: 14, height: 14)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(white: 0.7), lineWidth: 0.5))
                Text(node.name)
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                Spacer()
                Text("\(node.typeCount) types")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            metricRow("Instability (I)", String(format: "%.2f", node.instability))
            metricRow("Abstractness (A)", String(format: "%.2f", node.abstractness))
            metricRow("Afferent (Ca)", "\(node.afferentCoupling)")
            metricRow("Efferent (Ce)", "\(node.efferentCoupling)")
            metricRow("Distance from main seq.", String(format: "%.2f", node.distanceFromMainSequence))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(highlighted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(highlighted ? Color.accentColor : .clear, lineWidth: 1)
        )
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Fill = distance from the main sequence")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("green = balanced · red = zone of pain / uselessness")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 4)
    }
}
