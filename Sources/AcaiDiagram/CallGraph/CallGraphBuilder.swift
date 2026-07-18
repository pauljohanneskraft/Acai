import AcaiCore

/// Builds a static `CallGraph` from a `CodeArtifact`'s `Member.callSites`.
///
/// Unlike a sequence diagram, this is not a traversal from one entry point: every method (and,
/// outside a `.type` scope, every free function) in `scope` is treated as a caller and each of its
/// call sites becomes a direct edge to the method it targets, when that target can be resolved to a
/// known declaration. Resolved callees outside the scope are kept as leaf nodes so outgoing calls
/// stay visible; the scope only bounds which methods are *callers*.
///
/// A call site resolves by its `CallReceiver`: a `.type` receiver when `receiverType.methodName`
/// matches a member, a `.selfDispatch` when `callerType.methodName` matches a member (falling back to
/// a free function of that name, since a bare `foo()` is recorded as `.selfDispatch`), a `.free` when
/// `methodName` matches a free function.
/// The share of in-scope call sites that resolve is reported as `CallGraph.coverage`.
///
/// A value you instantiate with the scope/title and ask to `build(from:)` — kept off `CodeArtifact`
/// so the data model does not depend on the diagram layer.
public struct CallGraphBuilder: Sendable {
    public var scope: CallGraphScope
    public var title: String?

    public init(scope: CallGraphScope = .wholeCodebase, title: String? = nil) {
        self.scope = scope
        self.title = title
    }

    public func build(from artifact: CodeArtifact) -> CallGraph {
        var accumulator = CallGraphAccumulator(
            types: artifact.flattened(), freeFunctions: artifact.freestandingFunctions)
        accumulator.run(scope: scope)
        return accumulator.makeGraph(title: title)
    }
}

/// Accumulates nodes, weighted edges and resolution coverage for a `CallGraph`.
private struct CallGraphAccumulator {
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
        switch site.receiver {
        case .type(let receiver):
            guard typesByName[receiver] != nil, methodKeys.contains("\(receiver).\(site.methodName)") else {
                return nil
            }
            return (receiver, site.methodName, inScopeNames.contains(receiver))
        case .selfDispatch:
            if !callerType.isEmpty, methodKeys.contains("\(callerType).\(site.methodName)") {
                return (callerType, site.methodName, inScopeNames.contains(callerType))
            }
            // A bare `foo()` the parser optimistically tagged `.selfDispatch` may actually be a free
            // function; fall back to a free-function match before giving up.
            guard freeFunctionNames.contains(site.methodName) else { return nil }
            return ("", site.methodName, false)
        case .free:
            guard freeFunctionNames.contains(site.methodName) else { return nil }
            return ("", site.methodName, false)
        case .unknown, .unresolvedTypeName, .propertyChain, .ownProperty, .ownPropertyElement, .ownMethodReturn:
            // `CodeArtifact.resolvingCallSiteReceivers()` already promoted whatever it could to
            // `.type` before the graph is built; anything still in any deferred-resolution case
            // is genuinely unresolvable, not merely not-yet-tried — same as `.unknown`.
            return nil
        }
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
        ModuleResolver.standard.productName(forFilePath: location?.filePath ?? "")
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
