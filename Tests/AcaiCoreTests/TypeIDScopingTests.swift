import Testing
@testable import AcaiCore

@Suite("Type id scoping")
struct TypeIDScopingTests {
    private let path = "Sources/ModA/Outer.swift"
    private let modules = ModuleMap(roots: [], filePaths: [])

    private func type(
        _ id: String, kind: TypeKind = .class, nested: [TypeDeclaration] = [], extensionOf: String? = nil
    ) -> TypeDeclaration {
        TypeDeclaration(
            id: id, name: id.components(separatedBy: ".").last ?? id, qualifiedName: id, kind: kind,
            accessLevel: .internal, nestedTypes: nested, extensionOf: extensionOf,
            location: SourceLocation(filePath: path, line: 1, column: 1))
    }

    private var file: CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: CodeArtifact.SourceLanguage(rawValue: "fixture"), filePaths: [path]),
            types: [
                type("Outer", nested: [type("Outer.Inner")]),
                type("extension.Outer", kind: .extension, nested: [type("Outer.Extra")], extensionOf: "Outer")
            ],
            relationships: [
                Relationship(kind: .composition, source: "Outer", target: "Outer.Inner"),
                Relationship(kind: .dependency, source: "Outer", target: "Elsewhere")
            ])
    }

    @Test("Module scoping prefixes every declared id, nested ones and the edges naming them included")
    func moduleScoping() {
        let scoped = file.scopingTypeIDs(modules: modules)
        #expect(scoped.flattened().map(\.id)
            == ["ModA.Outer", "ModA.Outer.Inner", "extension.Outer", "ModA.Outer.Extra"])
        #expect(scoped.flattened().allSatisfy { $0.id == $0.qualifiedName || $0.kind == .extension })
        #expect(scoped.types[0].name == "Outer")
        #expect(scoped.types[1].extensionOf == "Outer")
        #expect(scoped.relationships.map { "\($0.source)->\($0.target)" }
            == ["ModA.Outer->ModA.Outer.Inner", "ModA.Outer->Elsewhere"])
        #expect(scoped.flattened().map(\.unqualifiedID) == ["Outer", "Outer.Inner", "extension.Outer", "Outer.Extra"])
    }

    @Test("A colliding id is re-scoped to its file, and only that type moves")
    func fileScoping() {
        let scoped = file.scopingTypeIDs(modules: modules)
        let other = CodeArtifact(
            metadata: scoped.metadata,
            types: [TypeDeclaration(
                id: "Outer", name: "Outer", qualifiedName: "Outer", kind: .struct, accessLevel: .internal,
                location: SourceLocation(filePath: "Sources/ModA/Other.swift", line: 1, column: 1))]
        ).scopingTypeIDs(modules: modules)
        let collisions = CollidingTypeIDs(files: [scoped, other])
        #expect(collisions.ids == ["ModA.Outer"])

        let disambiguated = collisions.disambiguating(scoped)
        #expect(disambiguated.flattened().map(\.id).prefix(2)
            == ["Sources/ModA/Outer.swift:Outer", "Sources/ModA/Outer.swift:Outer.Inner"])
        #expect(disambiguated.flattened().map(\.unqualifiedID).prefix(2) == ["Outer", "Outer.Inner"])
        #expect(disambiguated.relationships[0].source == "Sources/ModA/Outer.swift:Outer")
        #expect(collisions.disambiguating(other).types[0].id == "Sources/ModA/Other.swift:Outer")
    }

    @Test(
        "A file-private type is scoped to its file, nested types following",
        arguments: [AccessLevel.private, .filePrivate])
    func filePrivateScoping(access: AccessLevel) {
        var artifact = file
        artifact.types[0].accessLevel = access
        let scoped = artifact.scopingTypeIDs(modules: modules)
        #expect(scoped.flattened().map(\.id).prefix(2)
            == ["Sources/ModA/Outer.swift:Outer", "Sources/ModA/Outer.swift:Outer.Inner"])
        #expect(scoped.relationships[0].source == "Sources/ModA/Outer.swift:Outer")
    }

    @Test("Under several project roots the id carries the module ModuleMap reports, and unqualifies back")
    func projectQualifiedScoping() {
        let roots = ModuleMap(roots: ["apps/api", "apps/web"], filePaths: [])
        let file = CodeArtifact(
            metadata: .init(sourceLanguage: CodeArtifact.SourceLanguage(rawValue: "fixture")),
            types: [TypeDeclaration(
                id: "Foo", name: "Foo", qualifiedName: "Foo", kind: .class, accessLevel: .internal,
                location: SourceLocation(filePath: "apps/api/Sources/Core/Foo.swift", line: 1, column: 1))])
        let scoped = file.scopingTypeIDs(modules: roots).types[0]
        #expect(scoped.id == "api/Core.Foo")
        #expect(scoped.module == roots.module(forFilePath: "apps/api/Sources/Core/Foo.swift"))
        #expect(scoped.idScope.module == "api/Core")
        #expect(scoped.unqualifiedID == "Foo")
    }

    @Test("A reference spelled the way source code spells it resolves to the scoped id")
    func resolverMatchesUnqualifiedIDs() {
        let resolver = TypeIdentityResolver(types: file.scopingTypeIDs(modules: modules).types)
        #expect(resolver.resolve("Outer.Inner") == .resolved(TypeID("ModA.Outer.Inner")))
        #expect(resolver.resolve("Outer") == .resolved(TypeID("ModA.Outer")))
        #expect(resolver.resolve("ModA.Outer") == .resolved(TypeID("ModA.Outer")))
    }
}
