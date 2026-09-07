import SwiftUI
import AcaiDiagram
import AcaiRender

/// The package diagram's Inspector tab: selection-scoped, matching the Class/Freeform
/// convention. Nothing selected shows a placeholder; one module selected shows its full metrics
/// card plus a short cross-linked list of the modules it depends on / is depended on by, each
/// tappable to jump the selection there.
struct PackageDiagramInspector: View {
    let diagram: PackageDiagram
    let selectedNodeIDs: Set<String>
    /// Re-points the canvas/inspector selection at another module — used by the related-modules
    /// list so tapping a dependency jumps straight to it instead of making the user scroll to find it.
    let onSelect: (String) -> Void

    private static let ratio = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))

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
            Text(.app("View.PackageDiagramInspector.SelectModuleInspect"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var multiSelectionList: some View {
        let selected = diagram.nodes.filter { selectedNodeIDs.contains($0.id) }.sorted { $0.name < $1.name }
        return MultiSelectionInspector(
            items: selected,
            title: { Text(.app("View.PackageDiagramInspector.ModuleInflectTrueSelected \($0)")) },
            rowIcon: { _ in nil },
            rowLabel: \.name,
            rowDetail: { "\($0.typeCount) types" },
            onSelect: onSelect,
            bulkAction: nil
        )
    }

    private func moduleCard(_ node: PackageDiagram.Node, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: node.zoneColorHex))
                    .frame(width: 14, height: 14)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(white: 0.7), lineWidth: 0.5))
                Text(verbatim: node.name)
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                Spacer()
                Text(.app("View.PackageDiagramInspector.Types \(node.typeCount)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            MetricRow(.app("View.PackageDiagramInspector.InstabilityI"), node.instability.formatted(Self.ratio))
            MetricRow(.app("View.PackageDiagramInspector.AbstractnessA"), node.abstractness.formatted(Self.ratio))
            MetricRow(.app("View.PackageDiagramInspector.AfferentCa"), node.afferentCoupling.formatted())
            MetricRow(.app("View.PackageDiagramInspector.EfferentCe"), node.efferentCoupling.formatted())
            MetricRow(
                .app("View.PackageDiagramInspector.DistanceFromMainSeq"),
                node.distanceFromMainSequence.formatted(Self.ratio))
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
                relatedList(
                    title: .app("View.PackageDiagramInspector.DependsOn \(dependsOn.count)"),
                    nodes: dependsOn)
            }
            if !dependedOnBy.isEmpty {
                relatedList(
                    title: .app("View.PackageDiagramInspector.DependedOnBy \(dependedOnBy.count)"),
                    nodes: dependedOnBy)
            }
        }
    }

    private func relatedList(title: LocalizedStringResource, nodes: [PackageDiagram.Node]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localized: title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(nodes.sorted { $0.name < $1.name }, id: \.id) { related in
                Button {
                    onSelect(related.id)
                } label: {
                    HStack {
                        Text(verbatim: related.name)
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
            Text(.app("View.PackageDiagramInspector.FillDistanceMainSequence"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(.app("View.PackageDiagramInspector.GreenBalancedRedZone"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 4)
    }
}
