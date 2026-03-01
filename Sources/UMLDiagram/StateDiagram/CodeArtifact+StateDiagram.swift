import UMLCore

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
