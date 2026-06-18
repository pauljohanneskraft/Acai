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
        // An empty `typeName` selects a top-level (free) function entry point; otherwise the entry
        // is a method on the named type.
        let isFreeEntry = entryPoint.typeName.isEmpty
        let diagramTitle = title ?? (isFreeEntry
            ? "\(entryPoint.methodName)()"
            : "\(entryPoint.typeName).\(entryPoint.methodName)()")

        let lookups = SequenceTraversalLookups(types: types, freeFunctions: freestandingFunctions)

        let entryId: String
        let entryName: String
        let entryDecl: TypeDeclaration?
        let entryMember: Member
        if isFreeEntry {
            guard let function = lookups.freeFunctionsByName[entryPoint.methodName] else {
                return SequenceDiagram(title: diagramTitle)
            }
            // Free functions share the participant keyspace with types, so namespace their ids to
            // avoid colliding with a same-named type; the bare name stays the display label.
            entryId = SequenceTraversal.freeFunctionID(entryPoint.methodName)
            entryName = entryPoint.methodName
            entryDecl = nil
            entryMember = function
        } else {
            guard
                let entryType = lookups.typesByName[entryPoint.typeName],
                let member = lookups.membersByKey["\(entryPoint.typeName).\(entryPoint.methodName)"]
            else {
                return SequenceDiagram(title: diagramTitle)
            }
            entryId = entryType.name
            entryName = entryType.name
            entryDecl = entryType
            entryMember = member
        }

        var traversal = SequenceTraversal(
            lookups: lookups, typeMapping: typeMapping,
            maxDepth: maxDepth, participantKind: participantKind(for:)
        )
        traversal.run(
            entryId: entryId, entryName: entryName, entryDecl: entryDecl,
            isFreeFunction: isFreeEntry, entryMember: entryMember
        )

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
    /// Top-level functions keyed by name — the fallback target for an implicit-receiver call that
    /// doesn't match any method, and the resolver for a free-function entry point.
    let freeFunctionsByName: [String: Member]

    init(types: [TypeDeclaration], freeFunctions: [Member]) {
        typesByName = Dictionary(types.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var members: [String: Member] = [:]
        for type in types {
            for member in type.members {
                members["\(type.name).\(member.name)"] = member
            }
        }
        membersByKey = members
        freeFunctionsByName = Dictionary(
            freeFunctions.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first }
        )
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

    /// Participant id for a free (top-level) function. Namespaced so it can't collide with a type
    /// of the same name in the shared participant keyspace; the bare name remains the display label.
    static func freeFunctionID(_ name: String) -> String { "func:\(name)" }

    mutating func run(
        entryId: String, entryName: String, entryDecl: TypeDeclaration?,
        isFreeFunction: Bool, entryMember: Member
    ) {
        addParticipant(id: entryId, name: entryName, decl: entryDecl, isFreeFunction: isFreeFunction)
        traverse(callerId: entryId, member: entryMember, depth: 0)
    }

    private mutating func addParticipant(id: String, name: String, decl: TypeDeclaration?, isFreeFunction: Bool) {
        guard participantMap[id] == nil else { return }
        participantOrder.append(id)
        // The `id` keys message `from`/`to` (a type's simple name, or a namespaced free-function id);
        // `name` is the user-facing label. Using a declaration's qualified id here would diverge from
        // the messages for namespaced languages (Kotlin/Java), leaving messages orphaned. A free
        // function gets a `.control` lifeline to set it apart.
        participantMap[id] = SequenceDiagram.Participant(
            id: id,
            name: name,
            kind: isFreeFunction ? .control : participantKind(decl)
        )
    }

    private mutating func traverse(callerId: String, member: Member, depth: Int) {
        let key = "\(callerId).\(member.name)"
        guard !visited.contains(key), depth < maxDepth else { return }
        visited.insert(key)

        for site in member.callSites {
            // An implicit-receiver call that matches no method and no free function (a builtin, a
            // local variable's method, …) can't be drawn as a meaningful message — drop it rather
            // than emit a mislabeled self-call.
            guard let target = resolveTarget(site: site, callerId: callerId) else { continue }
            addParticipant(id: target.id, name: target.name, decl: target.decl, isFreeFunction: target.isFreeFunction)

            messages.append(SequenceDiagram.Message(
                from: callerId, to: target.id,
                label: site.methodName, kind: .synchronous, order: messageOrder
            ))
            messageOrder += 1

            if let calleeMember = target.member {
                traverse(callerId: target.id, member: calleeMember, depth: depth + 1)
            }

            messages.append(SequenceDiagram.Message(
                from: target.id, to: callerId,
                label: nil, kind: .return, order: messageOrder
            ))
            messageOrder += 1
        }
    }

    /// Resolves a call site to its participant id, callee body (if any), and whether the target is a
    /// free function. Returns `nil` for an **implicit-receiver** call that matches neither a method
    /// nor a free function, so the caller drops it — this covers a builtin (`print`), a call on a
    /// local variable, *and* a `self.x()` whose method is only on a base class not in the artifact.
    /// Dropping (rather than drawing a dead-end self-message) keeps the diagram clean and matches
    /// the call graph's resolution.
    ///
    /// - An **explicit** receiver always yields a participant (the named type), even when its body
    ///   isn't in the artifact — the message still shows the call, just without expansion.
    /// - An implicit receiver prefers a same-type method (self-call), then a free function (its own
    ///   lifeline).
    private func resolveTarget(site: CallSite, callerId: String) -> ResolvedTarget? {
        if let receiver = site.receiverType {
            let concrete = typeMapping[receiver] ?? receiver
            return ResolvedTarget(
                id: concrete, name: concrete,
                member: lookups.membersByKey["\(concrete).\(site.methodName)"],
                decl: lookups.typesByName[concrete],
                isFreeFunction: false
            )
        }
        let concreteCaller = typeMapping[callerId] ?? callerId
        if let member = lookups.membersByKey["\(concreteCaller).\(site.methodName)"] {
            return ResolvedTarget(
                id: concreteCaller, name: concreteCaller, member: member,
                decl: lookups.typesByName[concreteCaller], isFreeFunction: false
            )
        }
        if let function = lookups.freeFunctionsByName[site.methodName] {
            return ResolvedTarget(
                id: SequenceTraversal.freeFunctionID(site.methodName), name: site.methodName,
                member: function, decl: nil, isFreeFunction: true
            )
        }
        return nil
    }
}

/// A call site resolved to its sequence participant: the lifeline `id` (keys message `from`/`to`),
/// the user-facing `name`, the callee body to expand (`member`, `nil` when the body isn't in the
/// artifact), the type declaration (`nil` for a free function), and whether it is a free function
/// (gets a namespaced id + a `.control` lifeline).
private struct ResolvedTarget {
    let id: String
    let name: String
    let member: Member?
    let decl: TypeDeclaration?
    let isFreeFunction: Bool
}
