import CoreGraphics
import Testing
import AcaiCore
import AcaiDiagram
import AcaiQuality
import AcaiRender
@testable import AcaiApp

/// Covers #346. An empty canvas has to say whether anything the viewer did caused it, because only
/// then is there an undo to offer — so each diagram type's reading of its own configuration is
/// checked here rather than once per diagram type in a journey.
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

    private func codebase() -> Codebase {
        Codebase(name: "c", directoryPath: "/tmp")
    }

    /// Matches none of the fixture's type names, so every diagram ends up with nothing to draw.
    private var matchesNothing: AcaiQuality.Selector {
        AcaiQuality.Selector(typeGlob: "ZzNoSuchType*")
    }

    // MARK: - Class diagram

    @Test("An unnarrowed class diagram with no types blames the codebase, not the viewer")
    func classDiagramWithoutNarrowingBlamesTheCodebase() {
        let empty = CodeArtifact(metadata: .init(sourceLanguage: .swift, filePaths: []), types: [])
        let viewModel = ClassDiagramViewModel(codebase: codebase(), artifact: empty)
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

    @Test("A focus scope outranks a filter, because resetting it widens further")
    func classDiagramFocusOutranksFilter() {
        var configuration = ClassDiagramConfiguration()
        configuration.filter = matchesNothing
        configuration.focus = FocusConfiguration(rootTypeName: "ZzNoSuchType")
        let viewModel = ClassDiagramViewModel(
            codebase: codebase(), artifact: artifact(), configuration: configuration)
        #expect(viewModel.nodes.isEmpty)
        #expect(viewModel.emptyReason == .scope)
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
        // `isEmpty` reads the graph to avoid rebuilding the layout per render pass; the two must agree.
        #expect(viewModel.layout.nodes.isEmpty)
        #expect(viewModel.emptyReason == .filter)
    }

    @Test("A narrowed call-graph scope outranks a filter")
    func callGraphScopeOutranksFilter() {
        let viewModel = CallGraphViewModel(
            artifact: artifact(), scope: .type("ZzNoSuchType"), filter: matchesNothing)
        #expect(viewModel.isEmpty)
        #expect(viewModel.emptyReason == .scope)
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

        let filtered = PackageDiagramViewModel(artifact: artifact(), filter: matchesNothing)
        #expect(filtered.isEmpty)
        #expect(filtered.layout.nodes.isEmpty)
        #expect(filtered.emptyReason == .filter)
    }

    // MARK: - Sequence diagram

    @Test("A sequence trace's entry point is not an undo, so only its filter is reported")
    func sequenceDiagramReportsOnlyItsFilter() {
        let entryPoint = SequenceDiagramConfiguration(entryTypeName: "A", entryMethodName: "run")
        let untraceable = SequenceDiagramConfiguration(entryTypeName: "ZzNoSuchType", entryMethodName: "run")
        #expect(SequenceDiagramViewModel(artifact: artifact(), configuration: untraceable).emptyReason == .codebase)

        var filtered = entryPoint
        filtered.filter = matchesNothing
        let viewModel = SequenceDiagramViewModel(artifact: artifact(), configuration: filtered)
        #expect(viewModel.emptyReason == .filter)
    }

    // MARK: - State diagram

    @Test("An unconfigured or unfiltered state diagram blames the codebase")
    func stateDiagramWithoutFilterBlamesTheCodebase() {
        #expect(StateDiagramViewModel(artifact: artifact(), configuration: nil).emptyReason == .codebase)

        let configuration = StateDiagramConfiguration(typeName: "A", variableName: "state")
        #expect(
            StateDiagramViewModel(artifact: artifact(), configuration: configuration).emptyReason == .codebase
        )
    }

    @Test("A state-diagram filter that matches nothing is reported as the filter")
    func stateDiagramFilterIsReported() {
        var configuration = StateDiagramConfiguration(typeName: "A", variableName: "state")
        configuration.filter = matchesNothing
        let viewModel = StateDiagramViewModel(artifact: artifact(), configuration: configuration)
        #expect(viewModel.emptyReason == .filter)
    }
}
