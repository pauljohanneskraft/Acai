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
/// matches a member, a `.selfDispatch` when `callerType.methodName` matches (falling back to a
/// free function of that name, since a bare `foo()` is recorded as `.selfDispatch`), a `.free`
/// when `methodName` matches a free function. The resolved share is `CallGraph.coverage`.
///
/// Where a name matches several declarations — an overload set, or same-named free functions in
/// different files — ``OverloadResolver`` picks by the call's argument list and the call site's own
/// file; a call it cannot narrow to one is attributed to every candidate.
///
/// A value you instantiate with the scope/title and ask to `build(from:)`.
public struct CallGraphBuilder: Sendable {
    public var scope: CallGraphScope
    public var title: String?

    public init(scope: CallGraphScope = .wholeCodebase, title: String? = nil) {
        self.scope = scope
        self.title = title
    }

    public func build(from artifact: CodeArtifact) -> CallGraph {
        var accumulator = CallGraphAccumulator(
            types: artifact.flattened(),
            freeFunctions: artifact.freestandingFunctions,
            modules: ModuleMap(artifact: artifact))
        accumulator.run(scope: scope)
        return accumulator.makeGraph(title: title)
    }
}

/// One declaration a call site was attributed to: the member, the type that owns it (`nil` for a
/// free function), and whether that owner is inside the graph's scope.
private struct CallTarget {
    let type: TypeDeclaration?
    let member: Member
    let inScope: Bool
}

private struct CallGraphAccumulator {
    private let identityResolver: TypeIdentityResolver
    private let nodeIdentity: CallGraphNodeIdentity
    private let typesByID: [String: TypeDeclaration]
    /// Type id → member name → every declaration of that name, so an overload set arrives whole.
    private let membersByTypeID: [String: [String: [Member]]]
    private let freeFunctionsByName: [String: [Member]]
    private let allTypes: [TypeDeclaration]
    private let freeFunctions: [Member]
    private let modules: ModuleMap

    private var nodes: [String: CallGraph.Node] = [:]
    private var weights: [Pair: Int] = [:]
    private var resolved = 0
    private var total = 0

    private struct Pair: Hashable { let from: String; let to: String }

    init(types: [TypeDeclaration], freeFunctions: [Member], modules: ModuleMap) {
        allTypes = types
        self.freeFunctions = freeFunctions
        self.modules = modules
        identityResolver = TypeIdentityResolver(types: types)
        nodeIdentity = CallGraphNodeIdentity(types: types)
        typesByID = Dictionary(types.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        membersByTypeID = Dictionary(
            types.map { ($0.id, Dictionary(grouping: $0.members, by: \.name)) },
            uniquingKeysWith: { first, _ in first })
        freeFunctionsByName = Dictionary(grouping: freeFunctions, by: \.name)
    }

    mutating func run(scope: CallGraphScope) {
        let inScopeTypes = scopedTypes(scope)
        let inScopeIDs = Set(inScopeTypes.map(\.id))
        for type in inScopeTypes {
            for member in type.members where !member.callSites.isEmpty {
                let fromID = ensureNode(for: type, member: member, inScope: true)
                accumulate(
                    callSites: member.callSites, callerType: type,
                    fromID: fromID, inScopeIDs: inScopeIDs
                )
            }
        }
        // Free functions are callers everywhere except a single-type focus.
        for function in scopedFreeFunctions(scope) where !function.callSites.isEmpty {
            let fromID = ensureNode(for: nil, member: function, inScope: true)
            accumulate(callSites: function.callSites, callerType: nil, fromID: fromID, inScopeIDs: inScopeIDs)
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
        callSites: [CallSite], callerType: TypeDeclaration?, fromID: String, inScopeIDs: Set<String>
    ) {
        for site in callSites {
            let targets = resolve(site: site, callerType: callerType, inScopeIDs: inScopeIDs)
            guard !targets.isEmpty else {
                if constructsTypeWithImplicitInitializer(site) {
                    total += 1
                    resolved += 1
                } else if !site.isSpeculative {
                    total += 1
                }
                continue
            }
            // One call site, however many declarations its name could not be narrowed past.
            total += 1
            resolved += 1
            for target in targets {
                let toID = ensureNode(for: target.type, member: target.member, inScope: target.inScope)
                weights[Pair(from: fromID, to: toID), default: 0] += 1
            }
        }
    }

    private func resolve(
        site: CallSite, callerType: TypeDeclaration?, inScopeIDs: Set<String>
    ) -> [CallTarget] {
        switch site.receiver {
        case .type(let receiver):
            // A bare receiver name shared by two or more declared types can't be attributed to
            // either without guessing, so it is left unresolved rather than bound to a first match.
            guard case .resolved(let id) = identityResolver.resolve(receiver), let type = typesByID[id.value]
            else { return [] }
            return members(of: type, site: site, inScope: inScopeIDs.contains(id.value))
        case .selfDispatch:
            if let callerType {
                let own = members(of: callerType, site: site, inScope: inScopeIDs.contains(callerType.id))
                if !own.isEmpty { return own }
            }
            // A bare `foo()` tagged `.selfDispatch` may actually be a free function.
            return freeFunctionTargets(site: site)
        case .free:
            return freeFunctionTargets(site: site)
        case .unknown, .unresolvedTypeName, .propertyChain, .ownProperty, .ownPropertyElement, .ownMethodReturn:
            // `CodeArtifact.resolvingCallSiteReceivers()` already promoted whatever it could to
            // `.type`; anything still deferred here is genuinely unresolvable.
            return []
        }
    }

    private func members(of type: TypeDeclaration, site: CallSite, inScope: Bool) -> [CallTarget] {
        let candidates = membersByTypeID[type.id]?[site.methodName] ?? []
        return OverloadResolver(candidates: candidates)
            .targets(of: site)
            .map { CallTarget(type: type, member: $0, inScope: inScope) }
    }

    /// A free function is keyed by its file, so resolution prefers a declaration in the calling
    /// file: a file-local function shadows a same-named one elsewhere in the project. Only when the
    /// call's own file declares none does the whole project's set of that name apply.
    private func freeFunctionTargets(site: CallSite) -> [CallTarget] {
        let candidates = freeFunctionsByName[site.methodName] ?? []
        guard candidates.count > 1 else {
            return candidates.map { CallTarget(type: nil, member: $0, inScope: false) }
        }
        let sameFile = site.location.map { location in
            candidates.filter { $0.location?.filePath == location.filePath }
        } ?? []
        let pool = sameFile.isEmpty ? candidates : sameFile
        return OverloadResolver(candidates: pool)
            .targets(of: site)
            .map { CallTarget(type: nil, member: $0, inScope: false) }
    }

    /// A resolved construction with no declared initializer to target: there is no member for an edge,
    /// but the call is understood, so it counts toward coverage.
    private func constructsTypeWithImplicitInitializer(_ site: CallSite) -> Bool {
        guard site.isConstruction, case .type(let receiver) = site.receiver,
              case .resolved(let id) = identityResolver.resolve(receiver), let type = typesByID[id.value]
        else { return false }
        return !type.members.contains { $0.kind == .initializer }
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
        modules.module(forFilePath: location?.filePath ?? "")
    }

    // MARK: - Nodes

    private mutating func ensureNode(for type: TypeDeclaration?, member: Member, inScope: Bool) -> String {
        guard let type else { return ensureFreeFunctionNode(member, inScope: inScope) }
        let id = nodeIdentity.nodeID(for: member, in: type)
        return ensureNode(
            CallGraph.Node(
                id: id, typeName: nodeIdentity.nodeName(for: type), methodName: member.name,
                inScope: inScope, signature: member.callGraphParameterList),
            inScope: inScope)
    }

    private mutating func ensureFreeFunctionNode(_ function: Member, inScope: Bool) -> String {
        ensureNode(
            CallGraph.Node(
                id: nodeIdentity.nodeID(forFreeFunction: function), typeName: "",
                methodName: function.name, inScope: inScope,
                signature: function.callGraphParameterList,
                container: nodeIdentity.container(forFreeFunction: function)),
            inScope: inScope)
    }

    private mutating func ensureNode(_ node: CallGraph.Node, inScope: Bool) -> String {
        if var existing = nodes[node.id] {
            if inScope && !existing.inScope {
                existing.inScope = true
                nodes[node.id] = existing
            }
        } else {
            nodes[node.id] = node
        }
        return node.id
    }
}
