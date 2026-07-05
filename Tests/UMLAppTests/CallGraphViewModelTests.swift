import CoreGraphics
import Testing
import UMLCore
import UMLDiagram
import UMLRender
@testable import UMLApp

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
        #expect(vm.node(for: "A.run")?.inScope == true)
        #expect(vm.node(for: "B.work")?.inScope == false)
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
}
