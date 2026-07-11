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

    @Test func resolvesEdgeAndFullCoverage() {
        let graph = CallGraphBuilder().build(from: twoTypeArtifact())
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
                    accessLevel: .public,
                    members: [
                        Member(name: "run", kind: .method, accessLevel: .internal, callSites: [
                            CallSite(receiver: .type("B"), methodName: "work"),
                            CallSite(receiver: .type("Unknown"), methodName: "gone")
                        ])
                    ]
                ),
                TypeDeclaration(
                    id: "B", name: "B", qualifiedName: "B", kind: .class,
                    accessLevel: .public,
                    members: [Member(name: "work", kind: .method, accessLevel: .internal)]
                )
            ]
        )
        let graph = CallGraphBuilder().build(from: artifact)
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
                    accessLevel: .public,
                    members: [
                        Member(name: "run", kind: .method, accessLevel: .internal, callSites: [
                            CallSite(receiver: .selfDispatch, methodName: "helper")
                        ]),
                        Member(name: "helper", kind: .method, accessLevel: .internal)
                    ]
                )
            ]
        )
        let graph = CallGraphBuilder().build(from: artifact)
        #expect(graph.edges == [CallGraph.Edge(from: "A.run", to: "A.helper", weight: 1)])
    }

    @Test func repeatedCallAccumulatesWeight() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift"]),
            types: [
                TypeDeclaration(
                    id: "A", name: "A", qualifiedName: "A", kind: .class,
                    accessLevel: .public,
                    members: [
                        Member(name: "run", kind: .method, accessLevel: .internal, callSites: [
                            CallSite(receiver: .type("B"), methodName: "work"),
                            CallSite(receiver: .type("B"), methodName: "work")
                        ])
                    ]
                ),
                TypeDeclaration(
                    id: "B", name: "B", qualifiedName: "B", kind: .class,
                    accessLevel: .public,
                    members: [Member(name: "work", kind: .method, accessLevel: .internal)]
                )
            ]
        )
        let graph = CallGraphBuilder().build(from: artifact)
        #expect(graph.edges == [CallGraph.Edge(from: "A.run", to: "B.work", weight: 2)])
    }

    @Test func typeScopeBoundsCallersButKeepsCalleeLeaf() {
        let graph = CallGraphBuilder(scope: .type("A")).build(from: twoTypeArtifact())
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
        let graph = CallGraphBuilder(scope: .module("Core")).build(from: artifact)
        #expect(graph.nodes.first { $0.id == "A.run" }?.inScope == true)
        // B is out of module: still a resolved-callee leaf, not in scope.
        #expect(graph.nodes.first { $0.id == "B.work" }?.inScope == false)
    }

    @Test func freeFunctionCallerAndCalleeAppear() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift"]),
            types: [
                TypeDeclaration(
                    id: "A", name: "A", qualifiedName: "A", kind: .class,
                    accessLevel: .public,
                    members: [
                        Member(name: "run", kind: .method, accessLevel: .internal, callSites: [
                            CallSite(receiver: .free, methodName: "log")
                        ])
                    ]
                )
            ],
            freestandingFunctions: [
                Member(name: "log", kind: .method, accessLevel: .internal, callSites: [
                    CallSite(receiver: .free, methodName: "format")
                ]),
                Member(name: "format", kind: .method, accessLevel: .internal)
            ]
        )
        let graph = CallGraphBuilder().build(from: artifact)
        // A.run -> log (free function, implicit receiver), and log -> format (free->free).
        #expect(graph.edges == [
            CallGraph.Edge(from: "A.run", to: "log", weight: 1),
            CallGraph.Edge(from: "log", to: "format", weight: 1)
        ])
        #expect(graph.nodes.first { $0.id == "log" }?.isFreeFunction == true)
        #expect(graph.nodes.first { $0.id == "log" }?.label == "log")
    }

    @Test func sameTypeMethodWinsOverFreeFunctionOfSameName() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift"]),
            types: [
                TypeDeclaration(
                    id: "A", name: "A", qualifiedName: "A", kind: .class,
                    accessLevel: .public,
                    members: [
                        Member(name: "run", kind: .method, accessLevel: .internal, callSites: [
                            CallSite(receiver: .selfDispatch, methodName: "helper")
                        ]),
                        Member(name: "helper", kind: .method, accessLevel: .internal)
                    ]
                )
            ],
            freestandingFunctions: [Member(name: "helper", kind: .method, accessLevel: .internal)]
        )
        let graph = CallGraphBuilder().build(from: artifact)
        #expect(graph.edges == [CallGraph.Edge(from: "A.run", to: "A.helper", weight: 1)])
    }

    @Test func selfDispatchFallsBackToFreeFunctionWhenNoSelfMethod() {
        // A bare `foo()` is recorded as `.selfDispatch`; when the caller's type has no such method,
        // the resolver falls back to a free function of that name so the edge (and coverage) survives.
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift"]),
            types: [
                TypeDeclaration(
                    id: "A", name: "A", qualifiedName: "A", kind: .class,
                    accessLevel: .public,
                    members: [
                        Member(name: "run", kind: .method, accessLevel: .internal, callSites: [
                            CallSite(receiver: .selfDispatch, methodName: "format")
                        ])
                    ]
                )
            ],
            freestandingFunctions: [Member(name: "format", kind: .method, accessLevel: .internal)]
        )
        let graph = CallGraphBuilder().build(from: artifact)
        #expect(graph.coverage.resolved == 1)
        #expect(graph.edges == [CallGraph.Edge(from: "A.run", to: "format", weight: 1)])
    }

    @Test func typeScopeExcludesFreeFunctionsAsCallers() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift"]),
            types: [
                TypeDeclaration(
                    id: "A", name: "A", qualifiedName: "A", kind: .class,
                    accessLevel: .public,
                    members: [Member(name: "run", kind: .method, accessLevel: .internal)]
                )
            ],
            freestandingFunctions: [
                Member(name: "log", kind: .method, accessLevel: .internal, callSites: [
                    CallSite(receiver: .type("A"), methodName: "run")
                ])
            ]
        )
        // Whole codebase: the free function is a caller, so there's an edge.
        #expect(!CallGraphBuilder().build(from: artifact).edges.isEmpty)
        // Type scope on A: free functions are not callers, and A.run has no calls → no edges.
        #expect(CallGraphBuilder(scope: .type("A")).build(from: artifact).edges.isEmpty)
    }

    @Test func emptyWhenNoCallSites() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift"]),
            types: [TypeDeclaration(id: "A", name: "A", qualifiedName: "A", kind: .class, accessLevel: .public)]
        )
        let graph = CallGraphBuilder().build(from: artifact)
        #expect(graph.nodes.isEmpty)
        #expect(graph.edges.isEmpty)
        #expect(graph.coverage.fraction == 1)
    }
}
