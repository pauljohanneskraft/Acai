import UMLCore

/// Builds a `SequenceDiagram` by tracing the call graph from `entryPoint` through `Member.callSites`.
///
/// Each call site becomes a `synchronous` message; each return to the caller becomes a `return`
/// message. `typeMapping` resolves an abstract receiver (protocol/interface/base class) to the
/// concrete type whose body should be followed, so dynamic dispatch can still be traced.
///
/// A value you instantiate with the entry point/options and ask to `build(from:)` — kept off
/// `CodeArtifact` so the data model does not depend on the diagram layer.
///
/// - Note: requires parsers to populate `Member.callSites` (with a `CallReceiver.type` receiver for
///   cross-type calls); without it the diagram has the entry participant but no messages.
public struct SequenceDiagramBuilder: Sendable {
    public var entryPoint: (typeName: String, methodName: String)
    public var title: String?
    public var maxDepth: Int
    public var typeMapping: [String: String]

    public init(
        entryPoint: (typeName: String, methodName: String),
        title: String? = nil,
        maxDepth: Int = 5,
        typeMapping: [String: String] = [:]
    ) {
        self.entryPoint = entryPoint
        self.title = title
        self.maxDepth = maxDepth
        self.typeMapping = typeMapping
    }

    public func build(from artifact: CodeArtifact) -> SequenceDiagram {
        // An empty `typeName` selects a top-level (free) function entry point; otherwise the entry
        // is a method on the named type.
        let isFreeEntry = entryPoint.typeName.isEmpty
        let diagramTitle = title ?? (isFreeEntry
            ? "\(entryPoint.methodName)()"
            : "\(entryPoint.typeName).\(entryPoint.methodName)()")

        let lookups = SequenceTraversalLookups(types: artifact.types, freeFunctions: artifact.freestandingFunctions)

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
    /// free function, keyed on the call's ``CallReceiver``:
    ///
    /// - A **`.type`** receiver always yields a participant (the named type), even when its body isn't
    ///   in the artifact — the message still shows the call, just without expansion.
    /// - A **`.selfDispatch`** resolves to a same-type method, falling back to a free function of that
    ///   name (a bare `foo()` is recorded as `.selfDispatch`); if it matches neither (e.g. the method
    ///   lives only on a base class), the call is dropped rather than drawing a dead-end self-message.
    /// - A **`.free`** call resolves to a top-level function on its own lifeline.
    /// - **`.unknown`** (an unresolved receiver) is dropped.
    private func resolveTarget(site: CallSite, callerId: String) -> ResolvedTarget? {
        switch site.receiver {
        case .type(let receiver):
            let concrete = typeMapping[receiver] ?? receiver
            return ResolvedTarget(
                id: concrete, name: concrete,
                member: lookups.membersByKey["\(concrete).\(site.methodName)"],
                decl: lookups.typesByName[concrete],
                isFreeFunction: false
            )
        case .selfDispatch:
            let concreteCaller = typeMapping[callerId] ?? callerId
            if let member = lookups.membersByKey["\(concreteCaller).\(site.methodName)"] {
                return ResolvedTarget(
                    id: concreteCaller, name: concreteCaller, member: member,
                    decl: lookups.typesByName[concreteCaller], isFreeFunction: false
                )
            }
            // A bare `foo()` recorded as `.selfDispatch` may be a free function rather than a
            // same-type method; fall back to a free-function lifeline before dropping it.
            guard let function = lookups.freeFunctionsByName[site.methodName] else { return nil }
            return ResolvedTarget(
                id: SequenceTraversal.freeFunctionID(site.methodName), name: site.methodName,
                member: function, decl: nil, isFreeFunction: true
            )
        case .free:
            guard let function = lookups.freeFunctionsByName[site.methodName] else { return nil }
            return ResolvedTarget(
                id: SequenceTraversal.freeFunctionID(site.methodName), name: site.methodName,
                member: function, decl: nil, isFreeFunction: true
            )
        case .unknown:
            return nil
        }
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
