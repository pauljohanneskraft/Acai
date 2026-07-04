/// LCOM4-style lack-of-cohesion for a type: the number of connected components among its methods,
/// where two methods are connected when they touch a common stored property or one calls the other.
/// A result of `1` means the type is cohesive (one responsibility); higher counts mark a type doing
/// several unrelated jobs and a candidate for splitting. A value you instantiate and ask for
/// ``componentCount``.
///
/// Approximation, documented deliberately: parsers capture property *writes* (`assignments`) and
/// calls, but not reads, so two methods that only *read* the same field are not linked. The count is
/// therefore an upper bound on the true LCOM4 — tracked in issue #111 (capture field reads).
struct LcomAnalysis {
    let type: TypeDeclaration

    init(type: TypeDeclaration) {
        self.type = type
    }

    /// Number of connected components among the type's methods (0 for none, 1 when cohesive).
    var componentCount: Int {
        let methods = type.members.filter { $0.kind == .method }
        guard methods.count > 1 else { return methods.count }
        var components = DisjointSet(count: methods.count)
        linkBySharedField(methods, into: &components)
        linkByMutualCall(methods, into: &components)
        return components.componentCount
    }

    /// Union methods that write a common stored property (same field name, `self`/bare receiver).
    private func linkBySharedField(_ methods: [Member], into components: inout DisjointSet) {
        let properties = Set(type.members.filter { $0.kind == .property }.map(\.name))
        var writersByField: [String: [Int]] = [:]
        for (index, method) in methods.enumerated() {
            for assignment in method.assignments
            where assignment.targetReceiver == nil && properties.contains(assignment.targetName) {
                writersByField[assignment.targetName, default: []].append(index)
            }
        }
        for writers in writersByField.values {
            for writer in writers.dropFirst() { components.union(writers[0], writer) }
        }
    }

    /// Union methods where one calls the other (self/own-type receiver, matching a sibling method name).
    private func linkByMutualCall(_ methods: [Member], into components: inout DisjointSet) {
        let indexByName = Dictionary(
            methods.enumerated().map { ($1.name, $0) }, uniquingKeysWith: { first, _ in first })
        for (index, method) in methods.enumerated() {
            for call in method.callSites where callsSelf(call) {
                if let target = indexByName[call.methodName], target != index { components.union(index, target) }
            }
        }
    }

    /// Whether a call is dispatched on the type itself: no receiver (self call) or the type's own name.
    private func callsSelf(_ call: CallSite) -> Bool {
        guard let receiver = call.receiverType else { return true }
        return receiver == type.name
    }
}

/// Union-find (disjoint-set) over integer nodes, with path compression. A small value with behaviour —
/// the sanctioned way to carry graph logic without a static-function namespace.
private struct DisjointSet {
    private var parent: [Int]

    init(count: Int) {
        parent = Array(0..<count)
    }

    private mutating func root(of node: Int) -> Int {
        var current = node
        while parent[current] != current { current = parent[current] }
        var walk = node
        while parent[walk] != current { let next = parent[walk]; parent[walk] = current; walk = next }
        return current
    }

    mutating func union(_ lhs: Int, _ rhs: Int) {
        let left = root(of: lhs), right = root(of: rhs)
        if left != right { parent[left] = right }
    }

    /// The number of distinct components across all nodes.
    var componentCount: Int {
        var roots = self
        return Set((0..<parent.count).map { roots.root(of: $0) }).count
    }
}
