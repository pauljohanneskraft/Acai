import SwiftUI
import AcaiDiagram
import AcaiRender

/// The package diagram's Inspector tab: selection-scoped, matching the Class/Freeform
/// convention instead of the old "card for every module, re-sorted" behavior. Nothing selected
/// shows a placeholder; one module selected shows its full metrics card plus a short cross-linked
/// list of the modules it depends on / is depended on by, each tappable to jump the selection there.
struct PackageDiagramInspector: View {
    let diagram: PackageDiagram
    let selectedNodeIDs: Set<String>
    /// Re-points the canvas/inspector selection at another module — used by the related-modules
    /// list so tapping a dependency jumps straight to it instead of making the user scroll to find it.
    let onSelect: (String) -> Void

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        if selectedNodeIDs.isEmpty {
            emptyState
        } else if selectedNodeIDs.count == 1,
                  let node = diagram.nodes.first(where: { $0.id == selectedNodeIDs.first }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    moduleCard(node, highlighted: true)
                    relatedModulesSection(for: node)
                    legend
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            multiSelectionList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "cursorarrow.click")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("Select a module to inspect")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var multiSelectionList: some View {
        let selected = diagram.nodes.filter { selectedNodeIDs.contains($0.id) }.sorted { $0.name < $1.name }
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(selected.count) Modules Selected")
                    .font(.headline)
                ForEach(selected, id: \.id) { node in
                    Button {
                        onSelect(node.id)
                    } label: {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(hex: node.zoneColorHex))
                                .frame(width: 12, height: 12)
                            Text(node.name)
                                .font(.system(.subheadline, design: .monospaced))
                            Spacer()
                            Text("\(node.typeCount) types")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
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

    /// Modules `node` depends on ("Depends on") and modules that depend on `node` ("Depended on
    /// by"), each row jumping the selection there on tap — a "jump to a related element" action
    /// within a single diagram (cross-diagram `CodeElementReference` resolution is separate,
    /// not-yet-built work).
    private func relatedModulesSection(for node: PackageDiagram.Node) -> some View {
        let dependsOn = diagram.edges.filter { $0.from == node.id }
            .compactMap { edge in diagram.nodes.first { $0.id == edge.to } }
        let dependedOnBy = diagram.edges.filter { $0.to == node.id }
            .compactMap { edge in diagram.nodes.first { $0.id == edge.from } }

        return VStack(alignment: .leading, spacing: 8) {
            if !dependsOn.isEmpty {
                relatedList(title: "Depends On (\(dependsOn.count))", nodes: dependsOn)
            }
            if !dependedOnBy.isEmpty {
                relatedList(title: "Depended On By (\(dependedOnBy.count))", nodes: dependedOnBy)
            }
        }
    }

    private func relatedList(title: String, nodes: [PackageDiagram.Node]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(nodes.sorted { $0.name < $1.name }, id: \.id) { related in
                Button {
                    onSelect(related.id)
                } label: {
                    HStack {
                        Text(related.name)
                            .font(.system(.caption, design: .monospaced))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
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
