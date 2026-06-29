/// Tarjan's strongly-connected-components over a string-keyed adjacency map. Construct it with the
/// graph and read `cycles` — every SCC with more than one node, or a node with a self-loop, is a
/// dependency cycle. Deterministic: nodes are visited in sorted order.
struct StronglyConnectedComponents: Sendable {
    private let adjacency: [String: Set<String>]

    init(adjacency: [String: Set<String>]) {
        self.adjacency = adjacency
    }

    /// The non-trivial strongly-connected components — i.e. the dependency cycles.
    var cycles: [Set<String>] {
        var search = Search(adjacency: adjacency)
        return search.run()
    }

    /// Mutable working state for a single Tarjan traversal, kept off the value type itself.
    private struct Search {
        let adjacency: [String: Set<String>]
        var index = 0
        var indices: [String: Int] = [:]
        var lowlinks: [String: Int] = [:]
        var onStack: Set<String> = []
        var stack: [String] = []
        var components: [Set<String>] = []

        mutating func run() -> [Set<String>] {
            let nodes = Set(adjacency.keys).union(adjacency.values.flatMap { $0 }).sorted()
            for node in nodes where indices[node] == nil {
                strongConnect(node)
            }
            return components
        }

        private mutating func strongConnect(_ node: String) {
            indices[node] = index
            lowlinks[node] = index
            index += 1
            stack.append(node)
            onStack.insert(node)

            for next in (adjacency[node] ?? []).sorted() {
                if indices[next] == nil {
                    strongConnect(next)
                    lowlinks[node] = min(lowlinks[node]!, lowlinks[next]!)
                } else if onStack.contains(next) {
                    lowlinks[node] = min(lowlinks[node]!, indices[next]!)
                }
            }

            guard lowlinks[node] == indices[node] else { return }
            var component: Set<String> = []
            while let popped = stack.popLast() {
                onStack.remove(popped)
                component.insert(popped)
                if popped == node { break }
            }
            // Keep only genuine cycles: a multi-node component, or a single node that loops to itself.
            if component.count > 1 || (component.count == 1 && adjacency[node]?.contains(node) == true) {
                components.append(component)
            }
        }
    }
}
