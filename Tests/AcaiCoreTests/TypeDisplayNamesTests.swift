import Testing
@testable import AcaiCore

@Suite("Type display names")
struct TypeDisplayNamesTests {
    private let modules = ModuleMap(roots: [], filePaths: [])

    private func type(
        _ id: String, in path: String, access: AccessLevel = .internal, nested: [TypeDeclaration] = []
    ) -> TypeDeclaration {
        TypeDeclaration(
            id: id, name: id.components(separatedBy: ".").last ?? id, qualifiedName: id, kind: .class,
            accessLevel: access, nestedTypes: nested,
            location: SourceLocation(filePath: path, line: 1, column: 1))
    }

    private func names(_ types: [TypeDeclaration]) -> (CodeArtifact, TypeDisplayNames) {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: CodeArtifact.SourceLanguage(rawValue: "fixture")), types: types
        ).scopingTypeIDs(modules: modules)
        return (artifact, artifact.typeDisplayNames)
    }

    @Test("A name only one type has is shown as the source spells it, nested types included")
    func uniqueNameIsPlain() {
        let (artifact, names) = names([
            type(
                "Outer", in: "Sources/Core/Outer.swift",
                nested: [type("Outer.Inner", in: "Sources/Core/Outer.swift")]),
            type("Helper", in: "Sources/App/Helper.swift")
        ])
        #expect(artifact.flattened().map(\.id) == ["Core.Outer", "Core.Outer.Inner", "App.Helper"])
        #expect(artifact.flattened().map(names.name(for:)) == ["Outer", "Outer.Inner", "Helper"])
    }

    @Test("Two modules declaring the same name are each shown by their module-qualified id")
    func sharedNameIsDisambiguated() {
        let (_, names) = names([
            type("ThemeOption", in: "Sources/AcaiCLI/Theme.swift"),
            type("ThemeOption", in: "Sources/AcaiMCP/Theme.swift"),
            type("Server", in: "Sources/AcaiMCP/Server.swift")
        ])
        #expect(names.name(forID: "AcaiCLI.ThemeOption") == "AcaiCLI.ThemeOption")
        #expect(names.name(forID: "AcaiMCP.ThemeOption") == "AcaiMCP.ThemeOption")
        #expect(names.name(forID: "AcaiMCP.Server") == "Server")
    }

    @Test("A file-private namesake disambiguates both types, the private one by its file")
    func filePrivateNamesake() {
        let (_, names) = names([
            type("Helper", in: "Sources/Core/A.swift"),
            type("Helper", in: "Sources/Core/B.swift", access: .private)
        ])
        #expect(names.name(forID: "Core.Helper") == "Core.Helper")
        #expect(names.name(forID: "Sources/Core/B.swift:Helper") == "Sources/Core/B.swift:Helper")
    }

    @Test("An id no declared type carries, like a module or an external type, comes back unchanged")
    func unknownIDPassesThrough() {
        let (_, names) = names([type("Helper", in: "Sources/Core/A.swift")])
        #expect(names.name(forID: "Core") == "Core")
        #expect(names.name(forID: "Codable") == "Codable")
    }

    @Test("An unscoped artifact's ids are already what the source spells")
    func unscopedIDsAreUnchanged() {
        let names = TypeDisplayNames(types: [type("Outer.Inner", in: "Sources/Core/Outer.swift")])
        #expect(names.name(forID: "Outer.Inner") == "Outer.Inner")
    }
}
