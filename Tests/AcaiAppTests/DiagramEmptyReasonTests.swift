import CoreGraphics
import Testing
import AcaiCore
import AcaiDiagram
import AcaiQuality
import AcaiRender
@testable import AcaiApp

/// Covers #346. An empty canvas may only offer an undo that actually works, so each diagram type's
/// reason is checked here rather than once per diagram type in a journey.
@Suite("Diagram Empty Reason")
@MainActor
struct DiagramEmptyReasonTests {

    /// `A.run` calls `B.work`, and both types sit in one module, so every diagram type has something
    /// to draw before a filter is applied.
    private func artifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Core/A.swift", "Core/B.swift"]),
            types: [
                TypeDeclaration(
                    id: "A", name: "A", qualifiedName: "A", kind: .class, accessLevel: .public,
                    members: [
                        Member(name: "run", kind: .method, accessLevel: .internal, callSites: [
                            CallSite(receiver: .type("B"), methodName: "work")
                        ])
                    ],
                    location: SourceLocation(filePath: "Core/A.swift", line: 1, column: 1)
                ),
                TypeDeclaration(
                    id: "B", name: "B", qualifiedName: "B", kind: .class, accessLevel: .public,
                    members: [Member(name: "work", kind: .method, accessLevel: .internal)],
                    location: SourceLocation(filePath: "Core/B.swift", line: 1, column: 1)
                )
            ]
        )
    }

    /// No types at all, so no narrowing can be what emptied a canvas built from it.
    private func emptyArtifact() -> CodeArtifact {
        CodeArtifact(metadata: .init(sourceLanguage: .swift, filePaths: []), types: [])
    }

    /// `Loader.state` moves through idle → loading → loaded, so a state diagram built from it has
    /// real states a filter can hide (same shape as `StateDiagramViewModelTests`'s fixture).
    private func stateMachineArtifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift),
            types: [TypeDeclaration(
                id: "Loader", name: "Loader", qualifiedName: "Loader", kind: .class, accessLevel: .public,
                members: [
                    Member(
                        name: "state", kind: .property, accessLevel: .internal,
                        type: TypeReference(name: "State"),
                        initialValue: .init(kind: .enumCase, text: "idle")
                    ),
                    Member(
                        name: "load", kind: .method, accessLevel: .internal,
                        assignments: [
                            .init(targetName: "state", op: .assign, value: .init(kind: .enumCase, text: "loading")),
                            .init(targetName: "state", op: .assign, value: .init(kind: .enumCase, text: "loaded"))
                        ]
                    )
                ]
            )]
        )
    }

    private func codebase() -> Codebase {
        Codebase(name: "c", directoryPath: "/tmp")
    }

    /// Matches none of the fixture's type names.
    private var matchesNothing: AcaiQuality.Selector {
        AcaiQuality.Selector(typeGlob: "ZzNoSuchType*")
    }

    /// A package node is matched by `Selector.matchesModule(named:)`, which consults only the module
    /// facets, so `matchesNothing` would leave every module standing.
    private var matchesNoModule: AcaiQuality.Selector {
        AcaiQuality.Selector(module: "ZzNoSuchModule*")
    }

    // MARK: - Class diagram

    @Test("An unnarrowed class diagram with no types blames the codebase, not the viewer")
    func classDiagramWithoutNarrowingBlamesTheCodebase() {
        let viewModel = ClassDiagramViewModel(codebase: codebase(), artifact: emptyArtifact())
        #expect(viewModel.nodes.isEmpty)
        #expect(viewModel.emptyReason == .codebase)
    }

    @Test("A class-diagram filter that matches nothing is reported as the filter")
    func classDiagramFilterIsReported() {
        var configuration = ClassDiagramConfiguration()
        configuration.filter = matchesNothing
        let viewModel = ClassDiagramViewModel(
            codebase: codebase(), artifact: artifact(), configuration: configuration)
        #expect(viewModel.nodes.isEmpty)
        #expect(viewModel.emptyReason == .filter)
    }

    @Test("A minimum access level that hides every type is reported as the filter")
    func classDiagramMinimumAccessLevelIsReported() {
        let privateOnly = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Core/A.swift"]),
            types: [
                TypeDeclaration(
                    id: "A", name: "A", qualifiedName: "A", kind: .class, accessLevel: .private,
                    location: SourceLocation(filePath: "Core/A.swift", line: 1, column: 1)
                )
            ]
        )
        var configuration = ClassDiagramConfiguration()
        configuration.minimumAccessLevel = .public
        let viewModel = ClassDiagramViewModel(
            codebase: codebase(), artifact: privateOnly, configuration: configuration)
        #expect(viewModel.nodes.isEmpty)
        #expect(viewModel.emptyReason == .filter)
    }

    @Test("A focus on a type that isn't there is reported as the scope")
    func classDiagramFocusIsReported() {
        var configuration = ClassDiagramConfiguration()
        configuration.focus = FocusConfiguration(rootTypeName: "ZzNoSuchType")
        let viewModel = ClassDiagramViewModel(
            codebase: codebase(), artifact: artifact(), configuration: configuration)
        #expect(viewModel.nodes.isEmpty)
        #expect(viewModel.emptyReason == .scope)
    }

    @Test("A filter over a codebase with no types at all is the codebase's doing, not the filter's")
    func classDiagramFilterOverAnEmptyCodebaseBlamesTheCodebase() {
        var configuration = ClassDiagramConfiguration()
        configuration.filter = matchesNothing
        let viewModel = ClassDiagramViewModel(
            codebase: codebase(), artifact: emptyArtifact(), configuration: configuration)
        #expect(viewModel.nodes.isEmpty)
        // Clearing the filter would leave the canvas just as empty, so it must not be offered.
        #expect(viewModel.emptyReason == .codebase)
    }

    @Test("When no single undo would bring types back, neither is offered")
    func classDiagramBlamesTheCodebaseWhenNoSingleUndoHelps() {
        var configuration = ClassDiagramConfiguration()
        configuration.filter = matchesNothing
        configuration.focus = FocusConfiguration(rootTypeName: "ZzNoSuchType")
        let viewModel = ClassDiagramViewModel(
            codebase: codebase(), artifact: artifact(), configuration: configuration)
        #expect(viewModel.nodes.isEmpty)
        // Resetting the scope leaves the filter hiding everything, and clearing the filter leaves
        // the focus pointing at a type that isn't there — so neither button would do anything.
        #expect(viewModel.emptyReason == .codebase)
    }

    // MARK: - Call graph

    @Test("A whole-codebase call graph with no resolved calls blames the codebase")
    func callGraphWithoutNarrowingBlamesTheCodebase() {
        let viewModel = CallGraphViewModel(artifact: artifact(), scope: .wholeCodebase)
        #expect(viewModel.emptyReason == .codebase)
    }

    @Test("A call-graph filter that matches nothing is reported as the filter")
    func callGraphFilterIsReported() {
        let viewModel = CallGraphViewModel(
            artifact: artifact(), scope: .wholeCodebase, filter: matchesNothing)
        #expect(viewModel.isEmpty)
        #expect(viewModel.layout.nodes.isEmpty)
        #expect(viewModel.emptyReason == .filter)
    }

    @Test("A scope narrowed to a type that isn't there is reported as the scope")
    func callGraphScopeIsReported() {
        let viewModel = CallGraphViewModel(artifact: artifact(), scope: .type("ZzNoSuchType"))
        #expect(viewModel.isEmpty)
        #expect(viewModel.emptyReason == .scope)
    }

    @Test("A filter over a codebase with no calls at all is the codebase's doing, not the filter's")
    func callGraphFilterOverAnEmptyCodebaseBlamesTheCodebase() {
        let viewModel = CallGraphViewModel(
            artifact: emptyArtifact(), scope: .wholeCodebase, filter: matchesNothing)
        #expect(viewModel.isEmpty)
        #expect(viewModel.emptyReason == .codebase)
    }

    @Test("When no single undo would bring call sites back, neither is offered")
    func callGraphBlamesTheCodebaseWhenNoSingleUndoHelps() {
        let viewModel = CallGraphViewModel(
            artifact: artifact(), scope: .type("ZzNoSuchType"), filter: matchesNothing)
        #expect(viewModel.isEmpty)
        #expect(viewModel.emptyReason == .codebase)
    }

    @Test("Clearing a call-graph filter is reflected in the reason")
    func callGraphFilterCanBeCleared() {
        let viewModel = CallGraphViewModel(
            artifact: artifact(), scope: .wholeCodebase, filter: matchesNothing)
        #expect(viewModel.emptyReason == .filter)
        viewModel.applyFilter(nil)
        #expect(viewModel.emptyReason == .codebase)
        #expect(!viewModel.isEmpty)
    }

    // MARK: - Package diagram

    @Test("A package diagram has no scope to narrow, only a filter")
    func packageDiagramReportsOnlyItsFilter() {
        let unfiltered = PackageDiagramViewModel(artifact: artifact())
        #expect(unfiltered.emptyReason == .codebase)

        #expect(!unfiltered.isEmpty)

        let filtered = PackageDiagramViewModel(artifact: artifact(), filter: matchesNoModule)
        #expect(filtered.isEmpty)
        #expect(filtered.layout.nodes.isEmpty)
        #expect(filtered.emptyReason == .filter)
    }

    @Test("A filter over a codebase with no modules is the codebase's doing, not the filter's")
    func packageDiagramFilterOverAnEmptyCodebaseBlamesTheCodebase() {
        let viewModel = PackageDiagramViewModel(artifact: emptyArtifact(), filter: matchesNoModule)
        #expect(viewModel.isEmpty)
        #expect(viewModel.emptyReason == .codebase)
    }

    // MARK: - Sequence diagram

    @Test("A sequence trace's entry point is not an undo, so only its filter is reported")
    func sequenceDiagramReportsOnlyItsFilter() {
        let untraceable = SequenceDiagramConfiguration(entryTypeName: "ZzNoSuchType", entryMethodName: "run")
        let noTrace = SequenceDiagramViewModel(artifact: artifact(), configuration: untraceable)
        #expect(noTrace.isEmpty)
        #expect(noTrace.emptyReason == .codebase)

        var filtered = SequenceDiagramConfiguration(entryTypeName: "A", entryMethodName: "run")
        filtered.filter = matchesNothing
        let viewModel = SequenceDiagramViewModel(artifact: artifact(), configuration: filtered)
        // The generator keeps the entry-point participant whatever the filter says, so this is a
        // root-only trace rather than an empty one — and must still read as empty.
        #expect(viewModel.diagram.participants.count == 1)
        #expect(viewModel.isEmpty)
        #expect(viewModel.emptyReason == .filter)
    }

    @Test("A trace that was only ever its own root is not blamed on a filter that hid nothing")
    func sequenceDiagramRootOnlyTraceBlamesTheCodebase() {
        // `B.work` calls nothing, so this trace is one lifeline with or without the filter.
        var configuration = SequenceDiagramConfiguration(entryTypeName: "B", entryMethodName: "work")
        configuration.filter = matchesNothing
        let viewModel = SequenceDiagramViewModel(artifact: artifact(), configuration: configuration)
        #expect(viewModel.emptyReason == .codebase)
    }

    // MARK: - State diagram

    @Test("An unconfigured or failed state diagram is not an empty canvas to explain")
    func stateDiagramWithoutAResultIsNotEmpty() {
        let unconfigured = StateDiagramViewModel(artifact: stateMachineArtifact(), configuration: nil)
        #expect(!unconfigured.isEmpty)
        #expect(unconfigured.emptyReason == .codebase)

        // A failed analysis has its own error state, so it must not be blamed on the filter either.
        var missing = StateDiagramConfiguration(typeName: "Loader", variableName: "nope")
        missing.filter = matchesNothing
        let failed = StateDiagramViewModel(artifact: stateMachineArtifact(), configuration: missing)
        #expect(!failed.isEmpty)
        #expect(failed.emptyReason == .codebase)
    }

    @Test("A state machine with states to draw is not empty")
    func stateDiagramWithStatesIsNotEmpty() {
        let configuration = StateDiagramConfiguration(typeName: "Loader", variableName: "state")
        let viewModel = StateDiagramViewModel(artifact: stateMachineArtifact(), configuration: configuration)
        #expect(!viewModel.isEmpty)
        #expect(viewModel.emptyReason == .codebase)
    }

    @Test("A state-diagram filter that matches nothing is reported as the filter")
    func stateDiagramFilterIsReported() {
        var configuration = StateDiagramConfiguration(typeName: "Loader", variableName: "state")
        configuration.filter = matchesNothing
        let viewModel = StateDiagramViewModel(artifact: stateMachineArtifact(), configuration: configuration)
        // Filtering exempts the initial pseudo-state, so the diagram is not literally stateless —
        // but every state the viewer came to see is gone, so the canvas must say so.
        #expect(viewModel.diagram?.states.allSatisfy { $0.kind == .initial } == true)
        #expect(viewModel.isEmpty)
        #expect(viewModel.emptyReason == .filter)
    }
}
