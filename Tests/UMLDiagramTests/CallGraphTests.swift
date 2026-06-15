import Testing
@testable import UMLCore
@testable import UMLDiagram

@Suite("Call graph extraction")
struct CallGraphTests {

    /// Two types where `A.run` calls `B.work`; everything resolves.
    private func twoTypeArtifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift"]),
            types: [
                TypeDeclaration(
                    id: "A", name: "A", qualifiedName: "A", kind: .class,
                    members: [
                        Member(name: "run", kind: .method, callSites: [
                            CallSite(receiverType: "B", methodName: "work")
                        ])
                    ],
                    location: SourceLocation(filePath: "Core/A.swift", line: 1, column: 1)
                ),
                TypeDeclaration(
                    id: "B", name: "B", qualifiedName: "B", kind: .class,
                    members: [Member(name: "work", kind: .method)],
                    location: SourceLocation(filePath: "Core/B.swift", line: 1, column: 1)
                )
            ]
        )
    }

    @Test func resolvesEdgeAndFullCoverage() {
        let graph = twoTypeArtifact().callGraph()
        #expect(graph.coverage.resolved == 1)
        #expect(graph.coverage.total == 1)
        #expect(graph.coverage.fraction == 1)
        #expect(graph.edges == [CallGraph.Edge(from: "A.run", to: "B.work", weight: 1)])
        #expect(graph.nodes.map(\.id) == ["A.run", "B.work"])
    }

    @Test func unresolvedCallLowersCoverageButKeepsNoEdge() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift"]),
            types: [
                TypeDeclaration(
                    id: "A", name: "A", qualifiedName: "A", kind: .class,
                    members: [
                        Member(name: "run", kind: .method, callSites: [
                            CallSite(receiverType: "B", methodName: "work"),
                            CallSite(receiverType: "Unknown", methodName: "gone")
                        ])
                    ]
                ),
                TypeDeclaration(
                    id: "B", name: "B", qualifiedName: "B", kind: .class,
                    members: [Member(name: "work", kind: .method)]
                )
            ]
        )
        let graph = artifact.callGraph()
        #expect(graph.coverage.resolved == 1)
        #expect(graph.coverage.total == 2)
        #expect(graph.edges.count == 1)
        #expect(!graph.nodes.contains { $0.id == "Unknown.gone" })
    }

    @Test func implicitReceiverResolvesToSameType() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift"]),
            types: [
                TypeDeclaration(
                    id: "A", name: "A", qualifiedName: "A", kind: .class,
                    members: [
                        Member(name: "run", kind: .method, callSites: [
                            CallSite(receiverType: nil, methodName: "helper")
                        ]),
                        Member(name: "helper", kind: .method)
                    ]
                )
            ]
        )
        let graph = artifact.callGraph()
        #expect(graph.edges == [CallGraph.Edge(from: "A.run", to: "A.helper", weight: 1)])
    }

    @Test func repeatedCallAccumulatesWeight() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift"]),
            types: [
                TypeDeclaration(
                    id: "A", name: "A", qualifiedName: "A", kind: .class,
                    members: [
                        Member(name: "run", kind: .method, callSites: [
                            CallSite(receiverType: "B", methodName: "work"),
                            CallSite(receiverType: "B", methodName: "work")
                        ])
                    ]
                ),
                TypeDeclaration(
                    id: "B", name: "B", qualifiedName: "B", kind: .class,
                    members: [Member(name: "work", kind: .method)]
                )
            ]
        )
        let graph = artifact.callGraph()
        #expect(graph.edges == [CallGraph.Edge(from: "A.run", to: "B.work", weight: 2)])
    }

    @Test func typeScopeBoundsCallersButKeepsCalleeLeaf() {
        let graph = twoTypeArtifact().callGraph(scope: .type("A"))
        // Only A is a caller; B.work is pulled in as an out-of-scope leaf.
        let aNode = graph.nodes.first { $0.id == "A.run" }
        let bNode = graph.nodes.first { $0.id == "B.work" }
        #expect(aNode?.inScope == true)
        #expect(bNode?.inScope == false)
        #expect(graph.edges == [CallGraph.Edge(from: "A.run", to: "B.work", weight: 1)])
    }

    @Test func moduleScopeFiltersByBuildProduct() {
        var artifact = twoTypeArtifact()
        // Put B in a different module so a Core-scoped graph drops B as a caller.
        artifact.types[1].location = SourceLocation(filePath: "Other/B.swift", line: 1, column: 1)
        let graph = artifact.callGraph(scope: .module("Core"))
        #expect(graph.nodes.first { $0.id == "A.run" }?.inScope == true)
        // B is out of module: still a resolved-callee leaf, not in scope.
        #expect(graph.nodes.first { $0.id == "B.work" }?.inScope == false)
    }

    @Test func emptyWhenNoCallSites() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift"]),
            types: [TypeDeclaration(id: "A", name: "A", qualifiedName: "A", kind: .class)]
        )
        let graph = artifact.callGraph()
        #expect(graph.nodes.isEmpty)
        #expect(graph.edges.isEmpty)
        #expect(graph.coverage.fraction == 1)
    }
}
