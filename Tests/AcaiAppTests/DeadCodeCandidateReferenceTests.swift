import Foundation
import Testing
import AcaiCore
import AcaiDiagram
@testable import AcaiApp

@Suite("DeadCodeScan.Candidate code-element reference resolution")
struct DeadCodeCandidateReferenceTests {
    private func artifact(types: [TypeDeclaration]) -> CodeArtifact {
        CodeArtifact(metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift"]), types: types)
    }

    private func type(id: String, name: String) -> TypeDeclaration {
        TypeDeclaration(id: id, name: name, qualifiedName: id, kind: .class, accessLevel: .public)
    }

    @Test func aFreestandingFunctionResolvesToAnUntypedMethod() {
        let candidate = DeadCodeScan.Candidate(
            id: "helpers.swift:freeFunction()", typeName: nil, memberName: "freeFunction", location: nil)
        #expect(candidate.codeElementReference(in: artifact(types: []))
            == CodeElementReference.method(typeName: nil, methodName: "freeFunction"))
    }

    @Test func aMemberOfADeclaredTypeResolvesWithTheTypeName() {
        let candidate = DeadCodeScan.Candidate(
            id: "Foo.bar(Int)", typeName: "Foo", memberName: "bar", location: nil)
        let art = artifact(types: [type(id: "Foo", name: "Foo")])
        #expect(candidate.codeElementReference(in: art)
            == CodeElementReference.method(typeName: "Foo", methodName: "bar"))
    }

    /// A `typeName` naming no type in the artifact — a qualified id, for a simple name two modules
    /// both declare — leaves the member unqualified rather than inventing a type to point at.
    @Test func aTypeNameTheArtifactDoesNotDeclareLeavesTheMemberUnqualified() {
        let candidate = DeadCodeScan.Candidate(
            id: "ModuleA.Missing.bar()", typeName: "ModuleA.Missing", memberName: "bar", location: nil)
        #expect(candidate.codeElementReference(in: artifact(types: []))
            == CodeElementReference.method(typeName: nil, methodName: "bar"))
    }
}
