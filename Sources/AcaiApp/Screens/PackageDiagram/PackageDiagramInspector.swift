import SwiftUI
import AcaiDiagram
import AcaiRender

/// The package diagram's metrics sidebar. The canvas stays label-free (UML package shapes +
/// thickness-weighted dependency arrows); every number — instability, abstractness, afferent/
/// efferent coupling, type count, distance from the main sequence — is shown here instead.
struct PackageDiagramInspector: View {
    let diagram: PackageDiagram
    let selectedNodeIDs: Set<String>

    /// Selected modules first (in selection-agnostic name order), then the rest.
    private var orderedNodes: [PackageDiagram.Node] {
        let sorted = diagram.nodes.sorted { $0.name < $1.name }
        let selected = sorted.filter { selectedNodeIDs.contains($0.id) }
        let rest = sorted.filter { !selectedNodeIDs.contains($0.id) }
        return selected + rest
    }

    var body: some View {
        content
    }

    private var content: some View {
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

    private func moduleCard(_ node: PackageDiagram.Node, highlighted: Bool) -> some View {
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
            MetricRow("Instability (I)", String(format: "%.2f", node.instability))
            MetricRow("Abstractness (A)", String(format: "%.2f", node.abstractness))
            MetricRow("Afferent (Ca)", "\(node.afferentCoupling)")
            MetricRow("Efferent (Ce)", "\(node.efferentCoupling)")
            MetricRow("Distance from main seq.", String(format: "%.2f", node.distanceFromMainSequence))
        }
        .inspectorCard(highlighted: highlighted)
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
