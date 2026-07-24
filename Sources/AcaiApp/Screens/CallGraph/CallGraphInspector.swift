import SwiftUI
import AcaiDiagram

/// The call graph's sidebar. Leads with resolution coverage (how much of the observed call
/// traffic could be statically resolved), then lists each method with its in/out call counts.
/// Out-of-scope callee leaves are marked so the scoped focus stands out.
struct CallGraphInspector: View {
    let graph: CallGraph
    let selectedNodeIDs: Set<String>
    /// Mirrors the presenting `.inspector(isPresented:)` binding so this view can offer its own
    /// close affordance on iPhone, matching `ClassDiagramSidebar`'s pattern.
    @Binding var isPresented: Bool
    /// Passed down explicitly from `CallGraphView` — see `ClassDiagramSidebar.isCompactWidth`'s doc
    /// comment for why this isn't read via `@Environment(\.horizontalSizeClass)` in this view.
    var isCompactWidth: Bool

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

    /// Selected methods first (in name order), then the rest.
    private var orderedNodes: [CallGraph.Node] {
        let sorted = graph.nodes.sorted { $0.label < $1.label }
        let selected = sorted.filter { selectedNodeIDs.contains($0.id) }
        let rest = sorted.filter { !selectedNodeIDs.contains($0.id) }
        return selected + rest
    }

    var body: some View {
        #if os(iOS)
        if isCompactWidth {
            NavigationStack {
                content
                    .navigationTitle("Call Graph")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isPresented = false }
                                .accessibilityIdentifier("diagram.sidebarDoneButton")
                        }
                    }
            }
        } else {
            content
        }
        #else
        content
        #endif
    }

    private var content: some View {
        let counts = callCounts
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                coverageCard
                Text("Methods")
                    .font(.headline)
                ForEach(orderedNodes, id: \.id) { node in
                    methodCard(
                        node,
                        out: counts.out[node.id] ?? 0,
                        incoming: counts.in[node.id] ?? 0,
                        highlighted: selectedNodeIDs.contains(node.id)
                    )
                }
                legend
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private var legend: some View {
        Text("Solid = in scope · dashed “leaf” = resolved callee outside the scope")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.top, 4)
    }
}
