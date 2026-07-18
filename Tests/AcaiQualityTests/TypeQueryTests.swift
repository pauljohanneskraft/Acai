import Testing
import Foundation
import AcaiCore
@testable import AcaiQuality

/// Covers `TypeQuery` + `MemberFilter`: the type `Selector` narrows which types appear, the member
/// filter narrows which members (and drops types with no surviving member), and rows carry locations.
@Suite("Quality: TypeQuery")
struct TypeQueryTests {

    private func type(
        _ name: String,
        kind: TypeKind = .class,
        access: AccessLevel = .public,
        members: [Member] = []
    ) -> TypeDeclaration {
        TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: kind, accessLevel: access,
            members: members,
            location: SourceLocation(filePath: "\(name).swift", line: 1, column: 1))
    }

    private func method(_ name: String, params: Int, access: AccessLevel = .public) -> Member {
        Member(
            name: name, kind: .method, accessLevel: access,
            parameters: (0..<params).map { Parameter(internalName: "p\($0)") },
            location: SourceLocation(filePath: "M.swift", line: 5, column: 1))
    }

    private func artifact(_ types: [TypeDeclaration]) -> CodeArtifact {
        CodeArtifact(metadata: .init(sourceLanguage: .swift), types: types)
    }

    @Test func selectorNarrowsTypesAndRowsCarryLocations() {
        let service = type("Service", kind: .class, members: [method("run", params: 1)])
        let proto = type("Runnable", kind: .protocol)
        let rows = TypeQuery(
            artifact: artifact([service, proto]),
            selector: Selector(kind: .class)).rows

        #expect(rows.map(\.qualifiedName) == ["Service"])
        #expect(rows[0].location?.filePath == "Service.swift")
        #expect(rows[0].members.first?.location?.filePath == "M.swift")
    }

    @Test func activeMemberFilterDropsTypesWithNoMatch() {
        let wide = type("Wide", members: [method("f", params: 4)])
        let narrow = type("Narrow", members: [method("g", params: 1)])
        let rows = TypeQuery(
            artifact: artifact([wide, narrow]),
            members: MemberFilter(kind: .method, minParameters: 3)).rows

        // Only `Wide` keeps a member with 3+ parameters.
        #expect(rows.map(\.qualifiedName) == ["Wide"])
        #expect(rows[0].members.map(\.name) == ["f"])
    }

    @Test func emptyFilterKeepsEveryTypeAndMember() {
        let service = type("Service", members: [method("a", params: 0), method("b", params: 2)])
        let rows = TypeQuery(artifact: artifact([service])).rows
        #expect(rows.count == 1)
        #expect(rows[0].members.count == 2)
    }
}
