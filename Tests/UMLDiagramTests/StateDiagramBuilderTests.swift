import Testing
@testable import UMLDiagram
@testable import UMLCore

@Suite("State Diagram Builder")
struct StateDiagramBuilderTests {

    // MARK: - Fixtures

    private func loaderArtifact() -> CodeArtifact {
        let stateProperty = Member(
            name: "state", kind: .property,
            type: TypeReference(name: "State"),
            initialValue: .init(kind: .enumCase, text: "idle")
        )
        let load = Member(
            name: "load", kind: .method,
            assignments: [
                .init(targetName: "state", op: .assign, value: .init(kind: .enumCase, text: "loading")),
                .init(targetName: "state", op: .assign,
                      value: .init(kind: .enumCase, text: "loaded", receiverTypeName: "State"))
            ]
        )
        let fail = Member(
            name: "fail", kind: .method,
            assignments: [
                .init(targetName: "state", op: .assign, value: .init(kind: .enumCase, text: "failed"))
            ]
        )
        return CodeArtifact(
            metadata: .init(sourceLanguage: .swift),
            types: [TypeDeclaration(
                id: "Loader", name: "Loader", qualifiedName: "Loader", kind: .class,
                members: [stateProperty, load, fail]
            )]
        )
    }

    private func config(_ maxStates: Int = 20) -> StateDiagramConfiguration {
        StateDiagramConfiguration(typeName: "Loader", variableName: "state", maxStates: maxStates)
    }

    // MARK: - Happy Path

    @Test func statesComeFromInitialValueAndAssignments() throws {
        let diagram = try loaderArtifact().stateDiagram(configuration: config())
        let names = diagram.states.filter { $0.kind == .normal }.map(\.name)
        #expect(names == ["idle", "loading", "loaded", "failed"])
        #expect(diagram.states.contains { $0.kind == .initial })
        #expect(diagram.title == "Loader.state")
    }

    @Test func transitionsFormSequentialChains() throws {
        let diagram = try loaderArtifact().stateDiagram(configuration: config())
        // Chain inside load(): loading → loaded labeled load().
        #expect(diagram.transitions.contains {
            $0.from == "state_loading" && $0.to == "state_loaded" && $0.event == "load()"
        })
        // Initial value edge: __initial → idle, unlabeled.
        #expect(diagram.transitions.contains {
            $0.from == "__initial" && $0.to == "state_idle" && $0.event == nil
        })
        // Entry edges from the initial pseudo-state for each member's first assignment.
        #expect(diagram.transitions.contains {
            $0.from == "__initial" && $0.to == "state_loading" && $0.event == "load()"
        })
        #expect(diagram.transitions.contains {
            $0.from == "__initial" && $0.to == "state_failed" && $0.event == "fail()"
        })
    }

    @Test func qualifiedAndImplicitCasesCollapseIntoOneState() throws {
        // `.loaded` and `State.loaded` should produce a single state.
        let diagram = try loaderArtifact().stateDiagram(configuration: config())
        let loadedStates = diagram.states.filter { $0.name == "loaded" }
        #expect(loadedStates.count == 1)
    }

    // MARK: - Failures

    @Test func compoundAssignmentIsUnbounded() {
        var artifact = loaderArtifact()
        artifact.types[0].members.append(Member(
            name: "bump", kind: .method,
            assignments: [.init(targetName: "state", op: .compound,
                                value: .init(kind: .expression, text: "state += 1"))]
        ))
        #expect {
            try artifact.stateDiagram(configuration: config())
        } throws: { error in
            guard case .unboundedAssignment(let memberName, _, _) = error as? StateDiagramAnalysisError
            else { return false }
            return memberName == "bump"
        }
    }

    @Test func expressionValueIsUnbounded() {
        var artifact = loaderArtifact()
        artifact.types[0].members.append(Member(
            name: "refresh", kind: .method,
            assignments: [.init(targetName: "state", op: .assign,
                                value: .init(kind: .expression, text: "fetchState()"))]
        ))
        #expect {
            try artifact.stateDiagram(configuration: config())
        } throws: { error in
            guard case .unboundedAssignment = error as? StateDiagramAnalysisError else { return false }
            return true
        }
    }

    @Test func tooManyStatesFails() {
        #expect {
            try loaderArtifact().stateDiagram(configuration: config(3))
        } throws: { error in
            error as? StateDiagramAnalysisError == .tooManyStates(count: 4, limit: 3)
        }
    }

    @Test func unknownVariableFails() {
        #expect {
            try loaderArtifact().stateDiagram(
                configuration: .init(typeName: "Loader", variableName: "missing")
            )
        } throws: { error in
            error as? StateDiagramAnalysisError
                == .variableNotFound(typeName: "Loader", variableName: "missing")
        }
    }

    @Test func unknownTypeFails() {
        #expect(throws: StateDiagramAnalysisError.variableNotFound(
            typeName: "Nope", variableName: "state"
        )) {
            try loaderArtifact().stateDiagram(configuration: .init(typeName: "Nope", variableName: "state"))
        }
    }

    @Test func noAssignmentsFails() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift),
            types: [TypeDeclaration(
                id: "Bare", name: "Bare", qualifiedName: "Bare", kind: .class,
                members: [Member(name: "state", kind: .property)]
            )]
        )
        #expect(throws: StateDiagramAnalysisError.noAssignments(variableName: "state")) {
            try artifact.stateDiagram(configuration: .init(typeName: "Bare", variableName: "state"))
        }
    }

    @Test func expressionInitialValueIsIgnoredNotFatal() throws {
        var artifact = loaderArtifact()
        artifact.types[0].members[0].initialValue = .init(kind: .expression, text: "makeState()")
        let diagram = try artifact.stateDiagram(configuration: config())
        let names = diagram.states.filter { $0.kind == .normal }.map(\.name)
        #expect(names == ["loading", "loaded", "failed"])
    }

    // MARK: - Globals

    @Test func globalVariableDiagram() throws {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift),
            types: [TypeDeclaration(
                id: "Shadower", name: "Shadower", qualifiedName: "Shadower", kind: .class,
                members: [
                    Member(name: "mode", kind: .property),
                    Member(name: "set", kind: .method, assignments: [
                        .init(targetName: "mode", op: .assign,
                              value: .init(kind: .enumCase, text: "shadowed"))
                    ])
                ]
            )],
            freestandingFunctions: [Member(
                name: "escalate", kind: .method,
                assignments: [.init(targetName: "mode", op: .assign,
                                    value: .init(kind: .enumCase, text: "debug"))]
            )],
            globalVariables: [Member(
                name: "mode", kind: .property,
                initialValue: .init(kind: .enumCase, text: "normal")
            )]
        )
        let diagram = try artifact.stateDiagram(configuration: .init(variableName: "mode"))
        let names = diagram.states.filter { $0.kind == .normal }.map(\.name)
        // The Shadower type declares its own `mode`, so its write is excluded.
        #expect(names == ["normal", "debug"])
        #expect(diagram.title == "mode (global)")
    }

    // MARK: - DOT Rendering

    @Test func dotRendererEmitsStatesAndTransitions() throws {
        let diagram = try loaderArtifact().stateDiagram(configuration: config())
        let dot = StateDiagramDOTRenderer().render(diagram)
        #expect(dot.contains("loading"))
        #expect(dot.contains("load()"))
        #expect(dot.contains("->"))
    }
}
