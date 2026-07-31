import SwiftUI
import AcaiDiagram

/// The call graph's Inspector tab: selection-scoped, matching the Class/Freeform convention
/// instead of the old "card for every method, re-sorted" behavior. Nothing selected shows a
/// placeholder; one method selected shows its full detail card plus a short cross-linked list of
/// its callers/callees, each tappable to jump the selection there. The coverage card stays visible
/// regardless of selection — it's diagram-level information, not per-node detail.
struct CallGraphInspector: View {
    let graph: CallGraph
    let selectedNodeIDs: Set<String>
    /// Re-points the canvas/inspector selection at another method — used by the related-methods
    /// list so tapping a caller/callee jumps straight to it instead of making the user scroll to find it.
    let onSelect: (String) -> Void

    /// Outgoing / incoming edge counts per node id (weights summed).
    private var callCounts: (out: [String: Int], in: [String: Int]) {
        var outgoing: [String: Int] = [:]
        var incoming: [String: Int] = [:]
        for edge in graph.edges {
            outgoing[edge.from, default: 0] += edge.weight
            incoming[edge.to, default: 0] += edge.weight
        }
        return (outgoing, incoming)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                coverageCard
                selectionContent
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var selectionContent: some View {
        let counts = callCounts
        if selectedNodeIDs.isEmpty {
            emptyState
        } else if selectedNodeIDs.count == 1, let node = graph.nodes.first(where: { $0.id == selectedNodeIDs.first }) {
            VStack(alignment: .leading, spacing: 12) {
                methodCard(node, out: counts.out[node.id] ?? 0, incoming: counts.in[node.id] ?? 0, highlighted: true)
                relatedMethodsSection(for: node)
                legend
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
            Text("Select a method to inspect")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private var multiSelectionList: some View {
        let selected = graph.nodes.filter { selectedNodeIDs.contains($0.id) }.sorted { $0.label < $1.label }
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(selected.count) Methods Selected")
                .font(.headline)
            ForEach(selected, id: \.id) { node in
                Button {
                    onSelect(node.id)
                } label: {
                    HStack {
                        Image(systemName: node.isFreeFunction ? "function" : "f.cursive")
                            .foregroundStyle(.secondary)
                        Text(node.label)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var coverageCard: some View {
        let coverage = graph.coverage
        let percent = Int((coverage.fraction * 100).rounded())
        return VStack(alignment: .leading, spacing: 4) {
            Text("Coverage")
                .font(.headline)
            HStack {
                Text("Resolved call sites")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(coverage.resolved)/\(coverage.total)  (\(percent)%)")
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
                Text(node.label)
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if !node.inScope {
                    Text("leaf")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            MetricRow("Calls out", "\(out)")
            MetricRow("Called by", "\(incoming)")
        }
        .inspectorCard(highlighted: highlighted)
    }

    /// Methods `node` calls ("Calls") and methods that call `node` ("Called By"), each row jumping
    /// the selection there on tap (cross-diagram `CodeElementReference` resolution is separate,
    /// not-yet-built work — this stays within the one call graph already on screen).
    private func relatedMethodsSection(for node: CallGraph.Node) -> some View {
        let callees = graph.edges.filter { $0.from == node.id }
            .compactMap { edge in graph.nodes.first { $0.id == edge.to } }
        let callers = graph.edges.filter { $0.to == node.id }
            .compactMap { edge in graph.nodes.first { $0.id == edge.from } }

        return VStack(alignment: .leading, spacing: 8) {
            if !callees.isEmpty {
                relatedList(title: "Calls (\(callees.count))", nodes: callees)
            }
            if !callers.isEmpty {
                relatedList(title: "Called By (\(callers.count))", nodes: callers)
            }
        }
    }

    private func relatedList(title: String, nodes: [CallGraph.Node]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(nodes.sorted { $0.label < $1.label }, id: \.id) { related in
                Button {
                    onSelect(related.id)
                } label: {
                    HStack {
                        Text(related.label)
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
        Text("Solid = in scope · dashed “leaf” = resolved callee outside the scope")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.top, 4)
    }
}
