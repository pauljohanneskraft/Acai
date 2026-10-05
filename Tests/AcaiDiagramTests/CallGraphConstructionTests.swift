import Foundation
import Testing
@testable import AcaiCore
@testable import AcaiDiagram

@Suite("Call graph constructions")
struct CallGraphConstructionTests {
    private func artifact(constructedMembers: [Member], site: CallSite) -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift"]),
            types: [
                TypeDeclaration(
                    id: "A", name: "A", qualifiedName: "A", kind: .class, accessLevel: .public,
                    members: [Member(name: "run", kind: .method, accessLevel: .internal, callSites: [site])]
                ),
                TypeDeclaration(
                    id: "B", name: "B", qualifiedName: "B", kind: .struct, accessLevel: .public,
                    members: constructedMembers
                )
            ]
        )
    }

    @Test func constructingATypeWithOnlyAnImplicitInitializerIsResolvedWithoutAnEdge() {
        let graph = CallGraphBuilder().build(from: artifact(
            constructedMembers: [Member(name: "work", kind: .method, accessLevel: .internal)],
            site: CallSite(receiver: .type("B"), methodName: "init", isConstruction: true)))
        #expect(graph.coverage.resolved == 1)
        #expect(graph.coverage.total == 1)
        #expect(graph.edges.isEmpty)
    }

    @Test func constructingThroughADeclaredInitializerIsAnEdge() {
        let graph = CallGraphBuilder().build(from: artifact(
            constructedMembers: [Member(name: "init", kind: .initializer, accessLevel: .internal)],
            site: CallSite(receiver: .type("B"), methodName: "init", isConstruction: true)))
        #expect(graph.coverage.resolved == 1)
        #expect(graph.edges == [CallGraph.Edge(from: "A.run", to: "B.init", weight: 1)])
    }

    @Test func aMissingInitializerOnATypeThatDeclaresOthersStaysUnresolved() {
        let graph = CallGraphBuilder().build(from: artifact(
            constructedMembers: [Member(name: "init", kind: .initializer, accessLevel: .internal)],
            site: CallSite(receiver: .type("B"), methodName: "B", isConstruction: true)))
        #expect(graph.coverage.resolved == 0)
    }

    @Test func anOrdinaryCallToAMissingMemberStaysUnresolved() {
        let graph = CallGraphBuilder().build(from: artifact(
            constructedMembers: [],
            site: CallSite(receiver: .type("B"), methodName: "init")))
        #expect(graph.coverage.resolved == 0)
    }

    @Test func anUnresolvedSpeculativeSiteIsNotCounted() {
        let graph = CallGraphBuilder().build(from: artifact(
            constructedMembers: [],
            site: CallSite(receiver: .type("ThirdPartyJSON"), methodName: "subscript", isSpeculative: true)))
        #expect(graph.coverage.total == 0)
    }

    @Test func aResolvedSpeculativeSiteIsAnEdge() {
        let graph = CallGraphBuilder().build(from: artifact(
            constructedMembers: [Member(name: "subscript", kind: .subscript, accessLevel: .internal)],
            site: CallSite(receiver: .type("B"), methodName: "subscript", isSpeculative: true)))
        #expect(graph.coverage.resolved == 1)
        #expect(graph.coverage.total == 1)
        #expect(graph.edges == [CallGraph.Edge(from: "A.run", to: "B.subscript", weight: 1)])
    }

    @Test func theConstructionMarkerIsEncodedOnlyWhenSet() throws {
        let construction = CallSite(receiver: .type("B"), methodName: "init", isConstruction: true)
        let call = CallSite(receiver: .type("B"), methodName: "work")
        let encoder = JSONEncoder()
        #expect(try JSONDecoder().decode(CallSite.self, from: encoder.encode(construction)) == construction)
        #expect(try JSONDecoder().decode(CallSite.self, from: encoder.encode(call)) == call)
        let encodedCall = try #require(String(bytes: encoder.encode(call), encoding: .utf8))
        #expect(!encodedCall.contains("isConstruction"))
    }
}
