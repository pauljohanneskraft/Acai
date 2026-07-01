import UMLCore

/// Builds a value-flow `StateDiagram` for the variable selected in `configuration`, from a
/// `CodeArtifact`.
///
/// States are the distinct enumerable values (enum cases, literals, nil) that the variable is
/// assigned anywhere in the artifact, plus its declared initial value. Within one member body,
/// consecutive assignments form a transition chain labeled with that member; each member's first
/// assignment is also reachable from the initial pseudo-state.
///
/// A value you instantiate with the configuration and ask to `build(from:)` — kept off `CodeArtifact`
/// so the data model does not depend on the diagram layer. Build from a `resolvingExtensions()`-ed
/// artifact so members declared in extensions are visible.
///
/// Known limitations (documented behaviour, not bugs):
/// - Branch-insensitive: assignments in different `if`/`switch` arms of the same body appear as one
///   sequential chain.
/// - No scope tracking: a local variable shadowing the property is counted.
public struct StateDiagramBuilder: Sendable {
    public var configuration: StateDiagramConfiguration

    public init(configuration: StateDiagramConfiguration) {
        self.configuration = configuration
    }

    public func build(from artifact: CodeArtifact) throws -> StateDiagram {
        try StateAnalysis(artifact: artifact, configuration: configuration).buildDiagram()
    }
}

/// Internal worker that locates the variable, validates its assignments, and
/// assembles the diagram.
private struct StateAnalysis {
    let configuration: StateDiagramConfiguration
    /// The variable's declaring member (for its initial value).
    let variable: Member
    /// Members whose bodies assign the variable, with the relevant assignments,
    /// in declaration order.
    let mutatingMembers: [(memberName: String, assignments: [VariableAssignment])]

    init(artifact: CodeArtifact, configuration: StateDiagramConfiguration) throws {
        self.configuration = configuration
        if let typeName = configuration.typeName {
            guard let type = Self.findType(named: typeName, in: artifact.types),
                  let property = type.members.first(where: {
                      $0.kind == .property && !$0.isComputed && $0.name == configuration.variableName
                  })
            else {
                throw StateDiagramAnalysisError.variableNotFound(
                    typeName: typeName, variableName: configuration.variableName
                )
            }
            variable = property
            mutatingMembers = Self.collectFromType(
                type, freeFunctions: artifact.freestandingFunctions, configuration: configuration
            )
        } else {
            guard let global = artifact.globalVariables.first(where: { $0.name == configuration.variableName })
            else {
                throw StateDiagramAnalysisError.variableNotFound(
                    typeName: nil, variableName: configuration.variableName
                )
            }
            variable = global
            mutatingMembers = Self.collectGlobal(artifact, configuration: configuration)
        }
    }

    // MARK: - Collection

    private static func findType(named name: String, in types: [TypeDeclaration]) -> TypeDeclaration? {
        for type in types {
            if type.name == name || type.qualifiedName == name { return type }
            if let nested = findType(named: name, in: type.nestedTypes) { return nested }
        }
        return nil
    }

    /// Assignments to a property: bare/`self`-qualified targets and `Type.variable` static writes
    /// naming the declaring type from the type's own members, plus writes from free functions that
    /// mutate the type by reference (e.g. C's `void run(Download *d) { d->state = …; }`), which name
    /// the type as the assignment receiver. Keyed on the receiver *type*, so this stays
    /// language-agnostic and generalises to any by-reference struct mutation.
    private static func collectFromType(
        _ type: TypeDeclaration,
        freeFunctions: [Member],
        configuration: StateDiagramConfiguration
    ) -> [(String, [VariableAssignment])] {
        var result: [(String, [VariableAssignment])] = type.members.compactMap { member in
            let relevant = member.assignments.filter {
                $0.targetName == configuration.variableName
                    && ($0.targetReceiver == nil || $0.targetReceiver == type.name)
            }
            return relevant.isEmpty ? nil : (member.name, relevant)
        }
        for function in freeFunctions {
            let relevant = function.assignments.filter {
                $0.targetName == configuration.variableName && $0.targetReceiver == type.name
            }
            if !relevant.isEmpty { result.append((function.name, relevant)) }
        }
        return result
    }

    /// Assignments to a global: scanned across free functions and all type
    /// members, skipping types that declare their own property of the same name
    /// (those writes target the property, not the global).
    private static func collectGlobal(
        _ artifact: CodeArtifact,
        configuration: StateDiagramConfiguration
    ) -> [(String, [VariableAssignment])] {
        var result: [(String, [VariableAssignment])] = []
        func relevant(_ member: Member) -> [VariableAssignment] {
            member.assignments.filter {
                $0.targetName == configuration.variableName && $0.targetReceiver == nil
            }
        }
        for function in artifact.freestandingFunctions {
            let assignments = relevant(function)
            if !assignments.isEmpty { result.append((function.name, assignments)) }
        }
        func walk(_ types: [TypeDeclaration]) {
            for type in types {
                let shadowed = type.members.contains {
                    $0.kind == .property && $0.name == configuration.variableName
                }
                if !shadowed {
                    for member in type.members {
                        let assignments = relevant(member)
                        if !assignments.isEmpty {
                            result.append(("\(type.name).\(member.name)", assignments))
                        }
                    }
                }
                walk(type.nestedTypes)
            }
        }
        walk(artifact.types)
        return result
    }

    // MARK: - Diagram Assembly

    func buildDiagram() throws -> StateDiagram {
        try validateBounded()

        let initialKey = (variable.initialValue?.kind).flatMap { kind in
            kind == .expression ? nil : variable.initialValue.map(Self.stateKey)
        }

        var stateKeys: [String] = []
        func register(_ key: String) {
            if !stateKeys.contains(key) { stateKeys.append(key) }
        }
        if let initialKey { register(initialKey) }
        for (_, assignments) in mutatingMembers {
            for assignment in assignments { register(Self.stateKey(assignment.value)) }
        }

        guard !stateKeys.isEmpty else {
            throw StateDiagramAnalysisError.noAssignments(variableName: configuration.variableName)
        }
        guard stateKeys.count <= configuration.maxStates else {
            throw StateDiagramAnalysisError.tooManyStates(
                count: stateKeys.count, limit: configuration.maxStates
            )
        }

        let initialId = "__initial"
        var states = [StateDiagram.State(id: initialId, name: "", kind: .initial)]
        states += stateKeys.map {
            StateDiagram.State(id: Self.stateId(for: $0), name: $0, kind: .normal)
        }

        var transitions: [StateDiagram.Transition] = []
        var seen = Set<String>()
        func addTransition(from: String, to: String, event: String?) {
            let key = "\(from)→\(to)→\(event ?? "")"
            guard seen.insert(key).inserted else { return }
            transitions.append(StateDiagram.Transition(from: from, to: to, event: event))
        }

        if let initialKey {
            addTransition(from: initialId, to: Self.stateId(for: initialKey), event: nil)
        }
        for (memberName, assignments) in mutatingMembers {
            let event = "\(memberName)()"
            let ids = assignments.map { Self.stateId(for: Self.stateKey($0.value)) }
            guard let first = ids.first else { continue }
            addTransition(from: initialId, to: first, event: event)
            for (from, to) in zip(ids, ids.dropFirst()) {
                addTransition(from: from, to: to, event: event)
            }
        }

        return StateDiagram(title: title, states: states, transitions: transitions)
    }

    /// Throws when any assignment makes the state space non-enumerable. The
    /// declared initial value is exempt: a runtime initializer (e.g. `Date()`)
    /// is ignored rather than poisoning an otherwise enumerable variable.
    private func validateBounded() throws {
        for (memberName, assignments) in mutatingMembers {
            for assignment in assignments {
                if assignment.op == .compound {
                    throw StateDiagramAnalysisError.unboundedAssignment(
                        memberName: memberName,
                        reason: "the compound mutation '\(assignment.value.text)' "
                            + "of '\(assignment.targetName)' depends on the previous value",
                        location: assignment.location
                    )
                }
                if assignment.value.kind == .expression {
                    throw StateDiagramAnalysisError.unboundedAssignment(
                        memberName: memberName,
                        reason: "'\(assignment.targetName)' is assigned the "
                            + "non-enumerable expression '\(assignment.value.text)'",
                        location: assignment.location
                    )
                }
            }
        }
    }

    private var title: String {
        if let typeName = configuration.typeName {
            return "\(typeName).\(configuration.variableName)"
        }
        return "\(configuration.variableName) (global)"
    }

    /// Normalizes a value to its display/state key: enum-case receivers are
    /// stripped so `.loading` and `State.loading` collapse into one state.
    private static func stateKey(_ value: VariableAssignment.Value) -> String {
        value.text
    }

    private static func stateId(for key: String) -> String {
        let safe = key.map { ($0.isLetter || $0.isNumber) ? String($0) : "_" }.joined()
        return "state_\(safe)"
    }
}
