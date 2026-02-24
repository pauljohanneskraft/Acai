import UMLCore

// MARK: - CodeArtifact → DeploymentDiagram

extension CodeArtifact {

    /// Derives a `DeploymentDiagram` from this artifact.
    ///
    /// The `granularity` parameter controls how types are grouped into nodes:
    ///
    /// - `.fileLevel`: one node per source file; cross-file references → communication paths.
    /// - `.packageLevel` *(default)*: one node per namespace/package; cross-namespace
    ///   references → communication paths.
    /// - `.artifactLevel`: the entire artifact becomes a single node; combine multiple
    ///   `CodeArtifact` deploymentDiagrams externally to show inter-service topology.
    ///
    /// Communication paths are deduplicated — multiple references between the same
    /// pair of nodes produce exactly one path.
    public func deploymentDiagram(
        title: String? = nil,
        granularity: DiagramGranularity = .packageLevel
    ) -> DeploymentDiagram {
        let (nodes, typeToNodeId) = buildDeploymentNodes(granularity: granularity)
        let paths = buildCommunicationPaths(typeToNodeId: typeToNodeId)
        return DeploymentDiagram(title: title, nodes: nodes, communicationPaths: paths)
    }

    // MARK: Node building

    private func buildDeploymentNodes(granularity: DiagramGranularity)
        -> (nodes: [DeploymentDiagram.Node], typeToNodeId: [String: String])
    {
        switch granularity {

        case .fileLevel:
            return groupedDeploymentNodes(
                kind: .executionEnvironment,
                keyOf: { type in
                    guard let path = type.location?.filePath else { return nil }
                    return path.split(separator: "/").last.map(String.init) ?? path
                }
            )

        case .packageLevel:
            return groupedDeploymentNodes(
                kind: .server,
                keyOf: { $0.namespace }
            )

        case .artifactLevel:
            let name = metadata.sourceLanguage.rawValue.capitalized
            let nodeId = "artifact"
            let node = DeploymentDiagram.Node(
                id: nodeId,
                name: name,
                kind: .device,
                artifacts: types.map(Self.deploymentArtifact(from:))
            )
            var map: [String: String] = [:]
            for t in types { map[t.id] = nodeId; map[t.name] = nodeId }
            return ([node], map)
        }
    }

    /// Generic grouping helper: groups types by a key derived from each `TypeDeclaration`.
    private func groupedDeploymentNodes(
        kind: DeploymentDiagram.Node.Kind,
        keyOf: (TypeDeclaration) -> String?
    ) -> (nodes: [DeploymentDiagram.Node], typeToNodeId: [String: String]) {

        var grouped: [String: [TypeDeclaration]] = [:]
        var ungrouped: [TypeDeclaration] = []
        for type in types {
            if let key = keyOf(type) { grouped[key, default: []].append(type) }
            else { ungrouped.append(type) }
        }

        var nodes: [DeploymentDiagram.Node] = []
        var map: [String: String] = [:]

        for (group, groupTypes) in grouped.sorted(by: { $0.key < $1.key }) {
            let nodeId = Self.safeId(group)
            nodes.append(DeploymentDiagram.Node(
                id: nodeId,
                name: group,
                kind: kind,
                artifacts: groupTypes.map(Self.deploymentArtifact(from:))
            ))
            for t in groupTypes { map[t.id] = nodeId; map[t.name] = nodeId }
        }

        if !ungrouped.isEmpty {
            let rootName = metadata.sourceLanguage.rawValue.capitalized
            let rootId = "root"
            nodes.insert(DeploymentDiagram.Node(
                id: rootId,
                name: rootName,
                kind: .device,
                artifacts: ungrouped.map(Self.deploymentArtifact(from:))
            ), at: 0)
            for t in ungrouped { map[t.id] = rootId; map[t.name] = rootId }
        }

        return (nodes, map)
    }

    // MARK: Communication path detection

    /// Scans `relationships` for cross-node references and returns deduplicated paths.
    private func buildCommunicationPaths(
        typeToNodeId: [String: String]
    ) -> [DeploymentDiagram.CommunicationPath] {
        var seen: Set<String> = []
        var paths: [DeploymentDiagram.CommunicationPath] = []
        for rel in relationships {
            guard
                let fromId = typeToNodeId[rel.source],
                let toId   = typeToNodeId[rel.target],
                fromId != toId,
                seen.insert("\(fromId)→\(toId)").inserted
            else { continue }
            paths.append(DeploymentDiagram.CommunicationPath(from: fromId, to: toId))
        }
        return paths
    }

    // MARK: Shared helpers

    private static func safeId(_ s: String) -> String {
        s.map { c in (c.isLetter || c.isNumber) ? String(c) : "_" }.joined()
    }

    private static func deploymentArtifact(from type: TypeDeclaration) -> DeploymentDiagram.Artifact {
        DeploymentDiagram.Artifact(id: type.id, name: type.name, kind: deploymentArtifactKind(for: type.kind))
    }

    private static func deploymentArtifactKind(for kind: TypeKind) -> DeploymentDiagram.Artifact.Kind {
        switch kind {
        case .class, .object, .record:                          return .executable
        case .protocol, .interface, .trait:                     return .library
        case .struct:                                           return .library
        case .enum:                                             return .source
        case .typeAlias, .extension, .annotation, .module:      return .file
        }
    }
}

// MARK: - CodeArtifact → [StateDiagram]

extension CodeArtifact {

    /// Returns `StateDiagram` instances derived from this artifact.
    ///
    /// Two kinds of state machines are detected:
    ///
    /// 1. **Direct enum state machines** — each `enum` type with at least one case
    ///    becomes its own `StateDiagram`. Methods whose return type matches the enum
    ///    name (or `Self`) are inferred as transitions and shown via choice nodes.
    ///
    /// 2. **State-pattern hosts** — concrete types (class, struct, actor) that have a
    ///    stored property whose declared type is one of the artifact's own enums get an
    ///    additional diagram titled `HostType (property: EnumType)`.  This reflects the
    ///    common pattern of an object delegating its state to a dedicated enum.
    public func stateDiagrams() -> [StateDiagram] {
        // Index enum types that have at least one case
        let enumsByName: [String: TypeDeclaration] = Dictionary(
            types.filter { $0.kind == .enum && !$0.enumCases.isEmpty }
                 .map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var diagrams: [StateDiagram] = []

        // 1. One diagram per enum type
        for enumType in enumsByName.values.sorted(by: { $0.name < $1.name }) {
            diagrams.append(makeStateDiagram(from: enumType))
        }

        // 2. State-pattern hosts: types that hold a stored enum property
        for type in types where type.kind == .class || type.kind == .struct || type.kind == .object {
            for member in type.members where member.kind == .property && !member.isComputed {
                guard let propType = member.type,
                      let stateEnum = enumsByName[propType.name]
                else { continue }
                diagrams.append(makeStateDiagram(
                    from: stateEnum,
                    hostType: type,
                    statePropertyName: member.name
                ))
            }
        }

        return diagrams
    }

    // MARK: State diagram construction

    private func makeStateDiagram(
        from enumType: TypeDeclaration,
        hostType: TypeDeclaration? = nil,
        statePropertyName: String? = nil
    ) -> StateDiagram {
        let prefix = Self.safeId(enumType.id)
        let initialId = "\(prefix)__initial"

        let caseStates: [StateDiagram.State] = enumType.enumCases.map { c in
            StateDiagram.State(id: "\(prefix)_\(Self.safeId(c.name))", name: c.name, kind: .normal)
        }

        // Entry: initial → first case
        var transitions: [StateDiagram.Transition] = caseStates.first.map {
            [StateDiagram.Transition(from: initialId, to: $0.id)]
        } ?? []

        // Methods returning Self / the enum name → model via a choice node
        let transitionMethods = enumType.members.filter { member in
            guard member.kind == .method, let ret = member.type else { return false }
            return ret.name == enumType.name || ret.name == "Self"
        }
        var choiceStates: [StateDiagram.State] = []
        for method in transitionMethods {
            let choiceId = "\(prefix)__\(Self.safeId(method.name))"
            choiceStates.append(StateDiagram.State(id: choiceId, name: method.name, kind: .choice))
            for cs in caseStates {
                transitions.append(StateDiagram.Transition(from: cs.id, to: choiceId, event: method.name))
            }
            for cs in caseStates {
                transitions.append(StateDiagram.Transition(from: choiceId, to: cs.id))
            }
        }

        let allStates = [StateDiagram.State(id: initialId, name: "", kind: .initial)]
            + caseStates + choiceStates

        let title: String
        if let host = hostType, let prop = statePropertyName {
            title = "\(host.qualifiedName) (\(prop): \(enumType.name))"
        } else {
            title = enumType.qualifiedName
        }

        return StateDiagram(title: title, states: allStates, transitions: transitions)
    }
}

// MARK: - CodeArtifact → SequenceDiagram

extension CodeArtifact {

    /// Generates a `SequenceDiagram` by tracing the call graph starting from `entryPoint`.
    ///
    /// Given an entry method, the bridge follows `CallSite` records on each visited
    /// `Member` to discover which types are called and in what order. Each call site
    /// becomes a `synchronous` message; each return from a callee back to the caller
    /// becomes a `return` message.
    ///
    /// - Parameters:
    ///   - entryPoint: The starting method, identified by its owning type name and method name.
    ///   - title: Optional diagram title; defaults to `"TypeName.methodName()"`.
    ///   - maxDepth: Maximum call-graph traversal depth. Prevents infinite loops caused
    ///     by recursion or mutual calls. Defaults to `5`.
    ///
    /// - Note: This bridge requires parsers to populate `Member.callSites`. Without that
    ///   data the diagram will contain the entry participant but no messages. The
    ///   `CallSite.receiverType` field must be set for cross-type calls to be surfaced.
    ///
    /// # Example
    ///
    /// Given source like:
    /// ```swift
    /// class LoginService {
    ///     let auth: AuthService
    ///     func login(username: String, password: String) async throws -> Bool {
    ///         return try await auth.login(username: username, password: password)
    ///     }
    /// }
    /// class AuthService {
    ///     func login(username: String, password: String) async throws -> Bool { … }
    /// }
    /// ```
    ///
    /// Calling `artifact.sequenceDiagram(entryPoint: ("LoginService", "login"))` will
    /// produce:
    /// ```
    /// :LoginService      :AuthService
    ///      |                  |
    ///      |──── login ──────>|
    ///      |<─── return ──────|
    /// ```
    public func sequenceDiagram(
        entryPoint: (typeName: String, methodName: String),
        title: String? = nil,
        maxDepth: Int = 5
    ) -> SequenceDiagram {
        let diagramTitle = title ?? "\(entryPoint.typeName).\(entryPoint.methodName)()"

        // Build lookup: type name → type declaration
        let typesByName: [String: TypeDeclaration] = Dictionary(
            types.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Build lookup: (typeName, methodName) → Member
        var membersByKey: [String: Member] = [:]
        for type in types {
            for member in type.members {
                membersByKey["\(type.name).\(member.name)"] = member
            }
        }

        guard
            let entryType   = typesByName[entryPoint.typeName],
            let entryMember = membersByKey["\(entryPoint.typeName).\(entryPoint.methodName)"]
        else {
            return SequenceDiagram(title: diagramTitle)
        }

        // Ordered participant tracking (insertion order = diagram order)
        var participantOrder: [String] = []
        var participantMap: [String: SequenceDiagram.Participant] = [:]
        var messages: [SequenceDiagram.Message] = []
        var visited: Set<String> = []
        var messageOrder = 0

        func addParticipant(typeName: String) {
            guard participantMap[typeName] == nil else { return }
            let decl = typesByName[typeName]
            participantOrder.append(typeName)
            participantMap[typeName] = SequenceDiagram.Participant(
                id: decl?.id ?? typeName,
                name: typeName,
                kind: participantKind(for: decl)
            )
        }

        // Recursive traversal
        func traverse(callerTypeName: String, member: Member, depth: Int) {
            let key = "\(callerTypeName).\(member.name)"
            guard !visited.contains(key), depth < maxDepth else { return }
            visited.insert(key)

            for site in member.callSites {
                let receiverType = site.receiverType ?? callerTypeName
                addParticipant(typeName: receiverType)

                // Forward message: caller → callee
                messages.append(SequenceDiagram.Message(
                    from: callerTypeName,
                    to: receiverType,
                    label: site.methodName,
                    kind: .synchronous,
                    order: messageOrder
                ))
                messageOrder += 1

                // Recurse into callee if its implementation is available
                if let calleeMember = membersByKey["\(receiverType).\(site.methodName)"] {
                    traverse(callerTypeName: receiverType, member: calleeMember, depth: depth + 1)
                }

                // Return message: callee → caller
                messages.append(SequenceDiagram.Message(
                    from: receiverType,
                    to: callerTypeName,
                    label: nil,
                    kind: .return,
                    order: messageOrder
                ))
                messageOrder += 1
            }
        }

        addParticipant(typeName: entryType.name)
        traverse(callerTypeName: entryType.name, member: entryMember, depth: 0)

        let orderedParticipants = participantOrder.compactMap { participantMap[$0] }
        return SequenceDiagram(
            title: diagramTitle,
            participants: orderedParticipants,
            messages: messages
        )
    }

    // MARK: Shared sequence helper

    private func participantKind(for decl: TypeDeclaration?) -> SequenceDiagram.Participant.Kind {
        switch decl?.kind {
        case .protocol, .interface:             return .boundary
        case .class, .object, .record:          return .object
        case .struct:                           return .object
        case .enum:                             return .object
        case .none:                             return .object
        default:                                return .object
        }
    }
}
