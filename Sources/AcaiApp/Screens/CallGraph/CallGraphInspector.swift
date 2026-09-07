import SwiftUI
import AcaiDiagram

struct CallGraphInspector: View {
    let graph: CallGraph
    let selectedNodeIDs: Set<String>
    let onSelect: (String) -> Void

    private var callCounts: (out: [String: Int], in: [String: Int]) {
        var outgoing: [String: Int] = [:]
        var incoming: [String: Int] = [:]
        for edge in graph.edges {
            outgoing[edge.from, default: 0] += edge.weight
            incoming[edge.to, default: 0] += edge.weight
        }
        return (outgoing, incoming)
    }

    @ViewBuilder
    var body: some View {
        if selectedNodeIDs.count > 1 {
            multiSelectionList
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    coverageCard
                    selectionContent
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var selectionContent: some View {
        let counts = callCounts
        if selectedNodeIDs.isEmpty {
            emptyState
        } else if let node = graph.nodes.first(where: { $0.id == selectedNodeIDs.first }) {
            VStack(alignment: .leading, spacing: 12) {
                methodCard(node, out: counts.out[node.id] ?? 0, incoming: counts.in[node.id] ?? 0, highlighted: true)
                relatedMethodsSection(for: node)
                legend
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "cursorarrow.click")
                .font(.title)
                .foregroundStyle(.secondary)
            Text(.app("View.CallGraphInspector.SelectMethodInspect"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private var multiSelectionList: some View {
        let selected = graph.nodes.filter { selectedNodeIDs.contains($0.id) }.sorted { $0.label < $1.label }
        return MultiSelectionInspector(
            items: selected,
            title: { Text(.app("View.CallGraphInspector.MethodInflectTrueSelected \($0)")) },
            rowIcon: { $0.isFreeFunction ? "function" : "f.cursive" },
            rowLabel: \.label,
            rowDetail: nil,
            onSelect: onSelect,
            bulkAction: nil
        )
    }

    private var coverageCard: some View {
        let coverage = graph.coverage
        let percent = Int((coverage.fraction * 100).rounded())
        return VStack(alignment: .leading, spacing: 4) {
            Text(.app("View.CallGraphInspector.Coverage"))
                .font(.headline)
            HStack {
                Text(.app("View.CallGraphInspector.ResolvedCallSites"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: "\(coverage.resolved)/\(coverage.total)  (\(percent)%)")
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
    }

    private func methodCard(_ node: CallGraph.Node, out: Int, incoming: Int, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: node.isFreeFunction ? "function" : "f.cursive")
                    .foregroundStyle(.secondary)
                Text(verbatim: node.label)
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if !node.inScope {
                    Text(.app("View.CallGraphInspector.Leaf"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            MetricRow(.app("View.CallGraphInspector.CallsOut"), out.formatted())
            MetricRow(.app("View.CallGraphInspector.CalledBy"), incoming.formatted())
        }
        .inspectorCard(highlighted: highlighted)
    }

    /// Cross-diagram `CodeElementReference` resolution is separate, not-yet-built work — this stays
    /// within the one call graph already on screen.
    private func relatedMethodsSection(for node: CallGraph.Node) -> some View {
        let callees = graph.edges.filter { $0.from == node.id }
            .compactMap { edge in graph.nodes.first { $0.id == edge.to } }
        let callers = graph.edges.filter { $0.to == node.id }
            .compactMap { edge in graph.nodes.first { $0.id == edge.from } }

        return VStack(alignment: .leading, spacing: 8) {
            if !callees.isEmpty {
                relatedList(title: .app("View.CallGraphInspector.Calls \(callees.count)"), nodes: callees)
            }
            if !callers.isEmpty {
                relatedList(title: .app("View.CallGraphInspector.CalledByCount \(callers.count)"), nodes: callers)
            }
        }
    }

    private func relatedList(title: LocalizedStringResource, nodes: [CallGraph.Node]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localized: title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(nodes.sorted { $0.label < $1.label }, id: \.id) { related in
                Button {
                    onSelect(related.id)
                } label: {
                    HStack {
                        Text(verbatim: related.label)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
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
        Text(.app("View.CallGraphInspector.SolidScopeDashedLeaf"))
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.top, 4)
    }
}
