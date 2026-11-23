import Foundation
import Testing
@testable import AcaiCore

@Suite("Core: Weighted methods (WMC)")
struct WeightedMethodsTests {

    private func method(_ name: String, complexity: Int?) -> Member {
        Member(name: name, kind: .method, accessLevel: .internal, cyclomaticComplexity: complexity)
    }

    private func artifact(members: [Member]) -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: CodeArtifact.SourceLanguage(rawValue: "swift")),
            types: [
                TypeDeclaration(
                    id: "Service", name: "Service", qualifiedName: "Service", kind: .class,
                    accessLevel: .internal, members: members,
                    location: SourceLocation(filePath: "Sources/App/Service.swift", line: 1, column: 1))
            ]
        ).enriched()
    }

    private func metric(members: [Member]) -> CodeMetrics.TypeMetric? {
        artifact(members: members).computeMetrics().types.first { $0.name == "Service" }
    }

    @Test func weightedMethodsSumsComplexityOverMethodsAndInitialisers() {
        let measured = metric(members: [
            Member(name: "init", kind: .initializer, accessLevel: .internal, cyclomaticComplexity: 2),
            method("classify", complexity: 7),
            method("render", complexity: 3),
            Member(name: "name", kind: .property, accessLevel: .internal, cyclomaticComplexity: 4)
        ])
        // 2 + 7 + 3 — the property's complexity is not a method's and stays out.
        #expect(measured?.weightedMethods == 12)
        #expect(measured?.numberOfMethods == 2)
        #expect(measured?.maxCyclomaticComplexity == 7)
    }

    @Test func anUnmeasuredBodyContributesOne() {
        // A protocol requirement or an abstract declaration has no body to measure, so it weighs its
        // single path rather than nothing.
        let measured = metric(members: [method("a", complexity: nil), method("b", complexity: nil)])
        #expect(measured?.weightedMethods == 2)
        #expect(measured?.numberOfMethods == 2)
    }

    @Test func aTypeWithNoCallablesWeighsZero() {
        let measured = metric(members: [Member(name: "name", kind: .property, accessLevel: .internal)])
        #expect(measured?.weightedMethods == 0)
        #expect(measured?.numberOfMethods == 0)
    }

    @Test func responseForClassCountsDeclarationsNotTheirComplexity() {
        let members = [
            method("classify", complexity: 7),
            Member(name: "render", kind: .method, accessLevel: .internal, callSites: [
                CallSite(receiver: .type("Printer"), methodName: "draw")
            ], cyclomaticComplexity: 5)
        ]
        // Two declared methods plus one distinct call target — unchanged by the complexity weighting.
        #expect(metric(members: members)?.responseForClass == 3)
    }
}
