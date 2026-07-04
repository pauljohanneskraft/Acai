import Testing
@testable import UMLCore
@testable import UMLDiagram

/// Covers `CallGraphMetrics` (fan-in/out, recursion, coverage, hot-first ordering) and `MethodCycles`
/// (SCC over call-graph edges).
@Suite("Call graph metrics & cycles")
struct CallGraphMetricsTests {

    /// `A.run` → `B.work`; `B.work` carries a location.
    private func chainArtifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift),
            types: [
                TypeDeclaration(
                    id: "A", name: "A", qualifiedName: "A", kind: .class, accessLevel: .public,
                    members: [
                        Member(name: "run", kind: .method, accessLevel: .internal,
                            location: SourceLocation(filePath: "A.swift", line: 3, column: 1),
                            callSites: [CallSite(receiverType: "B", methodName: "work")])
                    ]),
                TypeDeclaration(
                    id: "B", name: "B", qualifiedName: "B", kind: .class, accessLevel: .public,
                    members: [
                        Member(name: "work", kind: .method, accessLevel: .internal,
                            location: SourceLocation(filePath: "B.swift", line: 7, column: 1))
                    ])
            ])
    }

    /// `A.ping` ↔ `B.pong` call each other — a two-method cycle.
    private func mutualRecursionArtifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift),
            types: [
                TypeDeclaration(
                    id: "A", name: "A", qualifiedName: "A", kind: .class, accessLevel: .public,
                    members: [
                        Member(name: "ping", kind: .method, accessLevel: .internal,
                            location: SourceLocation(filePath: "A.swift", line: 1, column: 1),
                            callSites: [CallSite(receiverType: "B", methodName: "pong")])
                    ]),
                TypeDeclaration(
                    id: "B", name: "B", qualifiedName: "B", kind: .class, accessLevel: .public,
                    members: [
                        Member(name: "pong", kind: .method, accessLevel: .internal,
                            location: SourceLocation(filePath: "B.swift", line: 1, column: 1),
                            callSites: [CallSite(receiverType: "A", methodName: "ping")])
                    ])
            ])
    }

    @Test func fanInFanOutAndLocationsAndOrdering() {
        let report = CallGraphMetrics(artifact: chainArtifact()).report
        #expect(report.coverage.fraction == 1)
        // Hottest first: B.work has fan-in 1, so it ranks ahead of A.run.
        #expect(report.nodes.first?.id == "B.work")
        let work = report.nodes.first { $0.id == "B.work" }
        #expect(work?.fanIn == 1)
        #expect(work?.fanOut == 0)
        #expect(work?.location?.filePath == "B.swift")
        let run = report.nodes.first { $0.id == "A.run" }
        #expect(run?.fanOut == 1)
        #expect(run?.isRecursive == false)
    }

    @Test func mutualRecursionIsFlaggedAndClustered() {
        let report = CallGraphMetrics(artifact: mutualRecursionArtifact()).report
        let allRecursive = report.nodes.allSatisfy(\.isRecursive)
        #expect(allRecursive)

        let clusters = MethodCycles(artifact: mutualRecursionArtifact()).clusters
        #expect(clusters.count == 1)
        #expect(clusters[0].methods.map(\.id) == ["A.ping", "B.pong"])
        #expect(clusters[0].methods.first?.location?.filePath == "A.swift")
    }

    @Test func noCyclesWhenAcyclic() {
        #expect(MethodCycles(artifact: chainArtifact()).clusters.isEmpty)
    }
}
