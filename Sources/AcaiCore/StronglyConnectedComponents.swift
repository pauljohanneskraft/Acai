/// Tarjan's strongly-connected-components over a string-keyed adjacency map. Construct it with the
/// graph and read `cycles` — every SCC with more than one node, or a node with a self-loop, is a
/// dependency cycle. Deterministic: nodes are visited in sorted order.
///
/// A generic graph algorithm reused across the engine: module/type dependency cycles
/// (`CycleFinder`) and method-level call cycles both build an adjacency map and read `cycles`.
public struct StronglyConnectedComponents: Sendable {
    private let adjacency: [String: Set<String>]

    public init(adjacency: [String: Set<String>]) {
        self.adjacency = adjacency
    }

    public var cycles: [Set<String>] {
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
                strongConnect(from: node)
            }
            return components
        }

        /// Tarjan's algorithm with an explicit frame stack instead of recursion, so depth is
        /// bounded by heap, not by call-stack size — a long dependency chain would otherwise
        /// overflow the stack one recursive call per edge.
        private mutating func strongConnect(from start: String) {
            var frames: [SearchFrame] = [makeFrame(for: start)]

            while var frame = frames.popLast() {
                var didDescend = false
                while frame.nextIndex < frame.neighbors.count {
                    let next = frame.neighbors[frame.nextIndex]
                    frame.nextIndex += 1
                    if indices[next] == nil {
                        frames.append(frame)
                        frames.append(makeFrame(for: next))
                        didDescend = true
                        break
                    } else if onStack.contains(next) {
                        lowlinks[frame.node] = min(lowlinks[frame.node]!, indices[next]!)
                    }
                }
                if didDescend { continue }

                finishComponent(for: frame.node)
                if let parentIndex = frames.indices.last {
                    let parent = frames[parentIndex].node
                    lowlinks[parent] = min(lowlinks[parent]!, lowlinks[frame.node]!)
                }
            }
        }

        private mutating func makeFrame(for node: String) -> SearchFrame {
            indices[node] = index
            lowlinks[node] = index
            index += 1
            stack.append(node)
            onStack.insert(node)
            return SearchFrame(node: node, neighbors: (adjacency[node] ?? []).sorted())
        }

        private mutating func finishComponent(for node: String) {
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

/// One in-progress `strongConnect` call: the node it's visiting, that node's sorted neighbors, and
/// how far through them it had gotten before it was suspended in favor of an unvisited neighbor.
private struct SearchFrame {
    let node: String
    let neighbors: [String]
    var nextIndex = 0
}
