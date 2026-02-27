import UMLCore

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
    ///   - typeMapping: An optional dictionary that maps abstract type names (protocols,
    ///     interfaces, base classes) to the concrete type whose implementation should be
    ///     followed when tracing the call graph.  This lets you resolve dynamic dispatch
    ///     so the diagram can be drawn even when the declared receiver type has no
    ///     directly accessible body.
    ///
    ///     Example: `["AuthServiceProtocol": "DefaultAuthService"]` — calls typed as
    ///     `AuthServiceProtocol` will appear in the diagram as `DefaultAuthService` and
    ///     the traversal will follow `DefaultAuthService`'s implementation.
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
        maxDepth: Int = 5,
        typeMapping: [String: String] = [:]
    ) -> SequenceDiagram {
        let diagramTitle = title ?? "\(entryPoint.typeName).\(entryPoint.methodName)()"

        let lookups = SequenceTraversalLookups(types: types)

        guard
            let entryType   = lookups.typesByName[entryPoint.typeName],
            let entryMember = lookups.membersByKey["\(entryPoint.typeName).\(entryPoint.methodName)"]
        else {
            return SequenceDiagram(title: diagramTitle)
        }

        var traversal = SequenceTraversal(
            lookups: lookups, typeMapping: typeMapping,
            maxDepth: maxDepth, participantKind: participantKind(for:)
        )
        traversal.run(entryType: entryType, entryMember: entryMember)

        let orderedParticipants = traversal.participantOrder.compactMap { traversal.participantMap[$0] }
        return SequenceDiagram(
            title: diagramTitle,
            participants: orderedParticipants,
            messages: traversal.messages
        )
    }

    // MARK: Shared sequence helper

    private func participantKind(for decl: TypeDeclaration?) -> SequenceDiagram.Participant.Kind {
        switch decl?.kind {
        case .protocol, .interface:
            return .boundary
        case .class, .object, .record:
            return .object
        case .struct:
            return .object
        case .enum:
            return .object
        case .none:
            return .object
        default:
            return .object
        }
    }
}

// MARK: - Sequence Diagram Traversal Helpers

/// Pre-built lookup tables for sequence diagram construction.
private struct SequenceTraversalLookups {
    let typesByName: [String: TypeDeclaration]
    let membersByKey: [String: Member]

    init(types: [TypeDeclaration]) {
        typesByName = Dictionary(types.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var members: [String: Member] = [:]
        for type in types {
            for member in type.members {
                members["\(type.name).\(member.name)"] = member
            }
        }
        membersByKey = members
    }
}

/// Mutable state for recursive sequence diagram traversal.
private struct SequenceTraversal {
    let lookups: SequenceTraversalLookups
    let typeMapping: [String: String]
    let maxDepth: Int
    let participantKind: (TypeDeclaration?) -> SequenceDiagram.Participant.Kind

    var participantOrder: [String] = []
    var participantMap: [String: SequenceDiagram.Participant] = [:]
    var messages: [SequenceDiagram.Message] = []
    private var visited: Set<String> = []
    private var messageOrder = 0

    init(
        lookups: SequenceTraversalLookups,
        typeMapping: [String: String],
        maxDepth: Int,
        participantKind: @escaping (TypeDeclaration?) -> SequenceDiagram.Participant.Kind
    ) {
        self.lookups = lookups
        self.typeMapping = typeMapping
        self.maxDepth = maxDepth
        self.participantKind = participantKind
    }

    mutating func run(entryType: TypeDeclaration, entryMember: Member) {
        addParticipant(typeName: entryType.name)
        traverse(callerTypeName: entryType.name, member: entryMember, depth: 0)
    }

    private mutating func addParticipant(typeName: String) {
        guard participantMap[typeName] == nil else { return }
        let decl = lookups.typesByName[typeName]
        participantOrder.append(typeName)
        participantMap[typeName] = SequenceDiagram.Participant(
            id: decl?.id ?? typeName,
            name: typeName,
            kind: participantKind(decl)
        )
    }

    private mutating func traverse(callerTypeName: String, member: Member, depth: Int) {
        let key = "\(callerTypeName).\(member.name)"
        guard !visited.contains(key), depth < maxDepth else { return }
        visited.insert(key)

        for site in member.callSites {
            let declaredType = site.receiverType ?? callerTypeName
            let concreteType = typeMapping[declaredType] ?? declaredType
            addParticipant(typeName: concreteType)

            messages.append(SequenceDiagram.Message(
                from: callerTypeName, to: concreteType,
                label: site.methodName, kind: .synchronous, order: messageOrder
            ))
            messageOrder += 1

            if let calleeMember = lookups.membersByKey["\(concreteType).\(site.methodName)"] {
                traverse(callerTypeName: concreteType, member: calleeMember, depth: depth + 1)
            }

            messages.append(SequenceDiagram.Message(
                from: concreteType, to: callerTypeName,
                label: nil, kind: .return, order: messageOrder
            ))
            messageOrder += 1
        }
    }}
