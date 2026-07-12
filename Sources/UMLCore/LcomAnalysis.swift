/// LCOM4-style lack-of-cohesion for a type: the number of connected components among its methods,
/// where two methods are connected when they touch a common stored property or one calls the other.
/// A result of `1` means the type is cohesive (one responsibility); higher counts mark a type doing
/// several unrelated jobs and a candidate for splitting. A value you instantiate and ask for
/// ``componentCount``.
///
/// Two methods are linked when they share access to a stored property by **read or write**
/// (``Member/fieldReads`` and ``Member/assignments``) or when one self-dispatches a call to the other.
public struct LcomAnalysis {
    let type: TypeDeclaration

    public init(type: TypeDeclaration) {
        self.type = type
    }

    /// Number of connected components among the type's methods (0 for none, 1 when cohesive).
    var componentCount: Int {
        let methods = type.members.filter { $0.kind == .method }
        guard methods.count > 1 else { return methods.count }
        return partition(of: methods).componentCount
    }

    /// The method-name clusters the type splits into — the *shape* of its lack of cohesion, turning the
    /// `lackOfCohesion` count into an actionable extract-class proposal ("these methods belong together;
    /// those form a separate responsibility"). One inner array per connected component; a cohesive type
    /// yields a single cluster. Method names within each cluster and the clusters themselves are sorted
    /// for stable output.
    public var components: [[String]] {
        let methods = type.members.filter { $0.kind == .method }
        guard methods.count > 1 else { return methods.isEmpty ? [] : [[methods[0].name]] }
        var partition = partition(of: methods)
        return partition.groups()
            .map { indices in indices.map { methods[$0].name }.sorted() }
            .sorted { ($0.first ?? "") < ($1.first ?? "") }
    }

    /// The disjoint-set over method indices, linked by shared field access and mutual self-calls.
    private func partition(of methods: [Member]) -> DisjointSet {
        var components = DisjointSet(count: methods.count)
        linkBySharedField(methods, into: &components)
        linkByMutualCall(methods, into: &components)
        return components
    }

    /// Union methods that access a common stored property — by read or write, same field name and a
    /// `self`/bare receiver.
    private func linkBySharedField(_ methods: [Member], into components: inout DisjointSet) {
        let properties = Set(type.members.filter(\.isStoredProperty).map(\.name))
        var accessorsByField: [String: [Int]] = [:]
        for (index, method) in methods.enumerated() {
            for assignment in method.assignments
            where assignment.targetReceiver == nil && properties.contains(assignment.targetName) {
                accessorsByField[assignment.targetName, default: []].append(index)
            }
            for read in method.fieldReads
            where read.receiver == nil && properties.contains(read.name) {
                accessorsByField[read.name, default: []].append(index)
            }
        }
        for accessors in accessorsByField.values {
            for accessor in accessors.dropFirst() { components.union(accessors[0], accessor) }
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

    /// Whether a call is dispatched on the type itself: a `self`-dispatch or an explicit receiver of
    /// the type's own name. Free-function and unresolved calls are *not* self (issue #111).
    private func callsSelf(_ call: CallSite) -> Bool {
        switch call.receiver {
        case .selfDispatch:
            return true
        case .type(let name):
            return name == type.name
        case .free, .unknown, .unresolvedTypeName, .propertyChain:
            return false
        }
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

    /// The nodes grouped by their connected component (one inner array per component).
    mutating func groups() -> [[Int]] {
        var byRoot: [Int: [Int]] = [:]
        for node in 0..<parent.count { byRoot[root(of: node), default: []].append(node) }
        return Array(byRoot.values)
    }
}
