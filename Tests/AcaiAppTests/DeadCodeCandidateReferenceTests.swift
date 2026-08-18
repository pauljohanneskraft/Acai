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

    /// `DeadCodeScan.Candidate` has no public memberwise initializer (only `Decodable`'s
    /// synthesized `init(from:)`), so build one through its own `Codable` conformance.
    private func candidate(id: String) throws -> DeadCodeScan.Candidate {
        try JSONDecoder().decode(DeadCodeScan.Candidate.self, from: Data("{\"id\":\"\(id)\"}".utf8))
    }

    @Test func bareFunctionIDWithNoDotResolvesToAnUntypedMethod() throws {
        let reference = try candidate(id: "freeFunction").codeElementReference(in: artifact(types: []))
        #expect(reference == CodeElementReference.method(typeName: nil, methodName: "freeFunction"))
    }

    @Test func typeDotMethodWhereTypeExistsResolvesWithTheTypeName() throws {
        let art = artifact(types: [type(id: "Foo", name: "Foo")])
        let reference = try candidate(id: "Foo.bar").codeElementReference(in: art)
        #expect(reference == CodeElementReference.method(typeName: "Foo", methodName: "bar"))
    }

    @Test func typeDotMethodWhereTypeDoesNotResolveFallsBackToTheWholeIDAsMethodName() throws {
        let reference = try candidate(id: "Missing.bar").codeElementReference(in: artifact(types: []))
        #expect(reference == CodeElementReference.method(typeName: nil, methodName: "Missing.bar"))
    }
}
