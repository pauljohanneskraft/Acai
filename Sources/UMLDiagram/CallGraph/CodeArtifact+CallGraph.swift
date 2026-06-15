import UMLCore

extension CodeArtifact {

    /// Builds a static `CallGraph` from this artifact's `Member.callSites`.
    ///
    /// Unlike `sequenceDiagram`, this is not a traversal from one entry point: every method (and,
    /// outside a `.type` scope, every free function) in `scope` is treated as a caller and each of
    /// its call sites becomes a direct edge to the method it targets, when that target can be
    /// resolved to a known declaration. Resolved callees outside the scope are kept as leaf nodes so
    /// outgoing calls stay visible; the scope only bounds which methods are *callers*.
    ///
    /// A call site resolves when `receiverType.methodName` matches a member, or — for an implicit
    /// receiver — when `callerType.methodName` matches a member or `methodName` matches a free
    /// function. The share of in-scope call sites that resolve is reported as `CallGraph.coverage`.
    ///
    /// - Parameters:
    ///   - scope: which methods/functions are treated as callers (a single type, a build module, or
    ///     the whole codebase).
    ///   - title: optional diagram title.
    public func callGraph(scope: CallGraphScope = .wholeCodebase, title: String? = nil) -> CallGraph {
        var builder = CallGraphBuilder(types: types, freeFunctions: freestandingFunctions)
        builder.run(scope: scope)
        return builder.makeGraph(title: title)
    }
}

/// Accumulates nodes, weighted edges and resolution coverage for a `CallGraph`.
private struct CallGraphBuilder {
    private let typesByName: [String: TypeDeclaration]
    private let methodKeys: Set<String>
    private let freeFunctionNames: Set<String>
    private let allTypes: [TypeDeclaration]
    private let freeFunctions: [Member]

    private var nodes: [String: CallGraph.Node] = [:]
    private var weights: [Pair: Int] = [:]
    private var resolved = 0
    private var total = 0

    private struct Pair: Hashable { let from: String; let to: String }

    init(types: [TypeDeclaration], freeFunctions: [Member]) {
        allTypes = types
        self.freeFunctions = freeFunctions
        typesByName = Dictionary(types.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var keys: Set<String> = []
        for type in types {
            for member in type.members { keys.insert("\(type.name).\(member.name)") }
        }
        methodKeys = keys
        freeFunctionNames = Set(freeFunctions.map(\.name))
    }

    mutating func run(scope: CallGraphScope) {
        let inScopeTypes = scopedTypes(scope)
        let inScopeNames = Set(inScopeTypes.map(\.name))
        for type in inScopeTypes {
            for member in type.members where !member.callSites.isEmpty {
                let fromID = ensureNode(type.name, member.name, inScope: true)
                accumulate(
                    callSites: member.callSites, callerType: type.name,
                    fromID: fromID, inScopeNames: inScopeNames
                )
            }
        }
        // Free functions are callers everywhere except a single-type focus.
        for function in scopedFreeFunctions(scope) where !function.callSites.isEmpty {
            let fromID = ensureNode("", function.name, inScope: true)
            accumulate(callSites: function.callSites, callerType: "", fromID: fromID, inScopeNames: inScopeNames)
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

    // MARK: - Accumulation

    private mutating func accumulate(
        callSites: [CallSite], callerType: String, fromID: String, inScopeNames: Set<String>
    ) {
        for site in callSites {
            total += 1
            guard let target = resolve(site: site, callerType: callerType, inScopeNames: inScopeNames) else { continue }
            resolved += 1
            let toID = ensureNode(target.typeName, target.methodName, inScope: target.inScope)
            weights[Pair(from: fromID, to: toID), default: 0] += 1
        }
    }

    /// Resolves a call site to a target node identity, or `nil` when it can't be matched.
    private func resolve(
        site: CallSite, callerType: String, inScopeNames: Set<String>
    ) -> (typeName: String, methodName: String, inScope: Bool)? {
        if let receiver = site.receiverType {
            guard typesByName[receiver] != nil, methodKeys.contains("\(receiver).\(site.methodName)") else {
                return nil
            }
            return (receiver, site.methodName, inScopeNames.contains(receiver))
        }
        // Implicit receiver: prefer a same-type method, then fall back to a free function.
        if !callerType.isEmpty, methodKeys.contains("\(callerType).\(site.methodName)") {
            return (callerType, site.methodName, inScopeNames.contains(callerType))
        }
        if freeFunctionNames.contains(site.methodName) {
            return ("", site.methodName, false)
        }
        return nil
    }

    // MARK: - Scope

    private func scopedTypes(_ scope: CallGraphScope) -> [TypeDeclaration] {
        switch scope {
        case .wholeCodebase:
            return allTypes
        case .type(let name):
            return allTypes.filter { $0.name == name }
        case .module(let module):
            return allTypes.filter { moduleName(of: $0.location) == module }
        }
    }

    private func scopedFreeFunctions(_ scope: CallGraphScope) -> [Member] {
        switch scope {
        case .wholeCodebase:
            return freeFunctions
        case .type:
            return []
        case .module(let module):
            return freeFunctions.filter { moduleName(of: $0.location) == module }
        }
    }

    private func moduleName(of location: SourceLocation?) -> String {
        BuildProduct.productName(forFilePath: location?.filePath ?? "")
    }

    // MARK: - Nodes

    private mutating func ensureNode(_ typeName: String, _ methodName: String, inScope: Bool) -> String {
        let id = typeName.isEmpty ? methodName : "\(typeName).\(methodName)"
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
