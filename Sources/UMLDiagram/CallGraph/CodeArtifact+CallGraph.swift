import UMLCore

extension CodeArtifact {

    /// Builds a static `CallGraph` from this artifact's `Member.callSites`.
    ///
    /// Unlike `sequenceDiagram`, this is not a traversal from one entry point: every method in
    /// `scope` is treated as a caller and each of its call sites becomes a direct edge to the
    /// method it targets, when that target can be resolved to a known declaration. Resolved
    /// callees outside the scope are kept as leaf nodes so outgoing calls stay visible; the
    /// scope only bounds which methods are *callers*.
    ///
    /// A call site resolves when `receiverType.methodName` (or, for an implicit receiver,
    /// `callerType.methodName`) matches a member in the artifact. The share of in-scope call
    /// sites that resolve is reported as `CallGraph.coverage`.
    ///
    /// - Parameters:
    ///   - scope: which methods are treated as callers (a single type, a build module, or the
    ///     whole codebase).
    ///   - title: optional diagram title.
    public func callGraph(scope: CallGraphScope = .wholeCodebase, title: String? = nil) -> CallGraph {
        var builder = CallGraphBuilder(types: types)
        builder.run(scope: scope)
        return builder.makeGraph(title: title)
    }
}

/// Accumulates nodes, weighted edges and resolution coverage for a `CallGraph`.
private struct CallGraphBuilder {
    private let typesByName: [String: TypeDeclaration]
    private let membersByKey: Set<String>
    private let allTypes: [TypeDeclaration]

    private var nodes: [String: CallGraph.Node] = [:]
    private var weights: [Pair: Int] = [:]
    private var resolved = 0
    private var total = 0

    private struct Pair: Hashable { let from: String; let to: String }

    init(types: [TypeDeclaration]) {
        allTypes = types
        typesByName = Dictionary(types.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var keys: Set<String> = []
        for type in types {
            for member in type.members { keys.insert("\(type.name).\(member.name)") }
        }
        membersByKey = keys
    }

    mutating func run(scope: CallGraphScope) {
        let inScopeTypes = scopedTypes(scope)
        let inScopeNames = Set(inScopeTypes.map(\.name))
        for type in inScopeTypes {
            for member in type.members where !member.callSites.isEmpty {
                let fromID = ensureNode(type.name, member.name, inScope: true)
                for site in member.callSites {
                    total += 1
                    let declaredType = site.receiverType ?? type.name
                    guard
                        typesByName[declaredType] != nil,
                        membersByKey.contains("\(declaredType).\(site.methodName)")
                    else { continue }
                    resolved += 1
                    let toID = ensureNode(
                        declaredType, site.methodName, inScope: inScopeNames.contains(declaredType)
                    )
                    weights[Pair(from: fromID, to: toID), default: 0] += 1
                }
            }
        }
    }

    func makeGraph(title: String?) -> CallGraph {
        let sortedNodes = nodes.values.sorted { $0.id < $1.id }
        let sortedEdges = weights
            .sorted { ($0.key.from, $0.key.to) < ($1.key.from, $1.key.to) }
            .map { CallGraph.Edge(from: $0.key.from, to: $0.key.to, weight: $0.value) }
        return CallGraph(
            title: title,
            nodes: sortedNodes,
            edges: sortedEdges,
            coverage: CallGraph.Coverage(resolved: resolved, total: total)
        )
    }

    // MARK: - Helpers

    private func scopedTypes(_ scope: CallGraphScope) -> [TypeDeclaration] {
        switch scope {
        case .wholeCodebase:
            return allTypes
        case .type(let name):
            return allTypes.filter { $0.name == name }
        case .module(let module):
            return allTypes.filter {
                BuildProduct.productName(forFilePath: $0.location?.filePath ?? "") == module
            }
        }
    }

    private mutating func ensureNode(_ typeName: String, _ methodName: String, inScope: Bool) -> String {
        let id = "\(typeName).\(methodName)"
        if var existing = nodes[id] {
            if inScope && !existing.inScope {
                existing.inScope = true
                nodes[id] = existing
            }
        } else {
            nodes[id] = CallGraph.Node(id: id, typeName: typeName, methodName: methodName, inScope: inScope)
        }
        return id
    }
}
