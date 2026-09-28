import CoreGraphics
import Testing
import AcaiCore
import AcaiDiagram
import AcaiRender
import AcaiQuality
@testable import AcaiApp

@Suite("Call Graph View Model")
@MainActor
struct CallGraphViewModelTests {

    /// `A.run` calls `B.work`; both methods exist, so the graph fully resolves.
    private func artifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift"]),
            types: [
                TypeDeclaration(
                    id: "A", name: "A", qualifiedName: "A", kind: .class,
                    accessLevel: .public,
                    members: [
                        Member(name: "run", kind: .method, accessLevel: .internal, callSites: [
                            CallSite(receiver: .type("B"), methodName: "work")
                        ])
                    ],
                    location: SourceLocation(filePath: "Core/A.swift", line: 1, column: 1)
                ),
                TypeDeclaration(
                    id: "B", name: "B", qualifiedName: "B", kind: .class,
                    accessLevel: .public,
                    members: [Member(name: "work", kind: .method, accessLevel: .internal)],
                    location: SourceLocation(filePath: "Core/B.swift", line: 1, column: 1)
                )
            ]
        )
    }

    @Test func buildsGraphForWholeCodebaseScope() {
        let vm = CallGraphViewModel(artifact: artifact(), scope: .wholeCodebase)
        #expect(vm.graph.nodes.map(\.id) == ["A.run", "B.work"])
        #expect(vm.graph.coverage.resolved == 1)
        #expect(vm.graph.coverage.total == 1)
    }

    @Test func typeScopeMarksOnlyScopedMethodsInScope() {
        let vm = CallGraphViewModel(artifact: artifact(), scope: .type("A"))
        #expect(vm.graph.nodes.first { $0.id == "A.run" }?.inScope == true)
        #expect(vm.graph.nodes.first { $0.id == "B.work" }?.inScope == false)
    }

    @Test func filterKeepsOnlyMatchingTypesAndDropsTheirEdges() {
        let vm = CallGraphViewModel(artifact: artifact(), scope: .wholeCodebase)
        vm.applyFilter(Selector(typeGlob: "A"))
        #expect(vm.graph.nodes.map(\.id) == ["A.run"])
        #expect(vm.graph.edges.isEmpty)
        #expect(vm.filter == Selector(typeGlob: "A"))
    }

    @Test func filterKeepsPositionOverridesForSurvivingNodes() {
        let vm = CallGraphViewModel(artifact: artifact(), scope: .wholeCodebase)
        vm.positionOverrides = ["A.run": CGPoint(x: 5, y: 6)]
        vm.applyFilter(Selector(typeGlob: "A"))
        #expect(vm.positionOverrides["A.run"] == CGPoint(x: 5, y: 6))
    }

    @Test func clearingFilterRestoresEveryNode() {
        let vm = CallGraphViewModel(artifact: artifact(), scope: .wholeCodebase, filter: Selector(typeGlob: "A"))
        #expect(vm.graph.nodes.map(\.id) == ["A.run"])
        vm.applyFilter(nil)
        #expect(vm.graph.nodes.map(\.id) == ["A.run", "B.work"])
    }

    @Test func selectionTogglesAndClears() {
        let vm = CallGraphViewModel(artifact: artifact(), scope: .wholeCodebase)
        vm.selectNode("A.run", extending: false)
        #expect(vm.selectedNodeIDs == ["A.run"])
        vm.selectNode("B.work", extending: true)
        #expect(vm.selectedNodeIDs == ["A.run", "B.work"])
        vm.clearSelection()
        #expect(vm.selectedNodeIDs.isEmpty)
    }

    @Test func restoredPositionsSeedOverrides() {
        let vm = CallGraphViewModel(
            artifact: artifact(), scope: .wholeCodebase,
            restoredPositions: ["A.run": CGPoint(x: 42, y: 24)]
        )
        #expect(vm.positionOverrides["A.run"] == CGPoint(x: 42, y: 24))
    }

    @Test func moveNodeUpdatesOverride() {
        let vm = CallGraphViewModel(artifact: artifact(), scope: .wholeCodebase)
        vm.moveNode("A.run", to: CGPoint(x: 10, y: 20))
        #expect(vm.positionOverrides["A.run"] == CGPoint(x: 10, y: 20))
    }

    @Test func exportsNonEmptyPNGData() throws {
        let vm = CallGraphViewModel(artifact: artifact(), scope: .wholeCodebase)
        let data = try vm.exportPNGData(scale: 1)
        // A valid PNG starts with the 8-byte signature.
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
    }

    // MARK: - Delta mode

    /// `A.run` always calls `C.help`; only the newer revision's `A.run` also calls the `work` method
    /// `B` gained, so that node and the edge into it are what the delta marks.
    private func artifact(callingBWork: Bool) -> CodeArtifact {
        var runCallSites = [CallSite(receiver: .type("C"), methodName: "help")]
        var bMembers: [Member] = []
        if callingBWork {
            runCallSites.append(CallSite(receiver: .type("B"), methodName: "work"))
            bMembers = [Member(name: "work", kind: .method, accessLevel: .internal)]
        }
        return CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift"]),
            types: [
                TypeDeclaration(
                    id: "A", name: "A", qualifiedName: "A", kind: .class, accessLevel: .public,
                    members: [Member(
                        name: "run", kind: .method, accessLevel: .internal, callSites: runCallSites)],
                    location: SourceLocation(filePath: "Core/A.swift", line: 1, column: 1)
                ),
                TypeDeclaration(
                    id: "B", name: "B", qualifiedName: "B", kind: .class, accessLevel: .public,
                    members: bMembers,
                    location: SourceLocation(filePath: "Core/B.swift", line: 1, column: 1)
                ),
                TypeDeclaration(
                    id: "C", name: "C", qualifiedName: "C", kind: .class, accessLevel: .public,
                    members: [Member(name: "help", kind: .method, accessLevel: .internal)],
                    location: SourceLocation(filePath: "Core/C.swift", line: 1, column: 1)
                )
            ]
        )
    }

    @Test func comparisonArtifactMarksAddedElements() {
        let vm = CallGraphViewModel(
            artifact: artifact(callingBWork: true), scope: .wholeCodebase,
            comparisonArtifact: artifact(callingBWork: false))

        #expect(vm.isDeltaMode)
        #expect(vm.nodeDeltaStatus(id: "B.work") == .added)
        #expect(vm.nodeDeltaColor(id: "B.work") != nil)
        #expect(vm.edgeDeltaColor(from: "A.run", to: "B.work") != nil)
        // Everything the revisions share carries no badge and no tint.
        #expect(vm.nodeDeltaStatus(id: "C.help") == nil)
        #expect(vm.nodeDeltaColor(id: "C.help") == nil)
        #expect(vm.edgeDeltaColor(from: "A.run", to: "C.help") == nil)
    }

    @Test func noComparisonArtifactMeansNoDeltaStatus() {
        let vm = CallGraphViewModel(artifact: artifact(callingBWork: true), scope: .wholeCodebase)
        #expect(!vm.isDeltaMode)
        #expect(vm.nodeDeltaStatus(id: "B.work") == nil)
        #expect(vm.edgeDeltaColor(from: "A.run", to: "B.work") == nil)
    }
}
