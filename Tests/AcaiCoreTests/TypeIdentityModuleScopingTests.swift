import Testing
@testable import AcaiCore

/// A same-module simple name resolves despite a cross-module collision (#299).
@Suite("Core: Module-scoped type identity resolution")
struct TypeIdentityModuleScopingTests {

    private func artifact(_ types: [TypeDeclaration]) -> CodeArtifact {
        CodeArtifact(metadata: .init(sourceLanguage: .swift), types: types)
    }

    /// `Parser` and `Renderer` are separate build modules, each declaring a nested `Node`. A bare
    /// reference to `Node` from within one of those modules is not actually ambiguous, even though
    /// the simple name `Node` is shared globally.
    private func moduleScopedNodeFixture() -> CodeArtifact {
        let parserNode = TypeDeclaration(
            id: "Parser.Node", name: "Node", qualifiedName: "Parser.Node", kind: .class,
            accessLevel: .public,
            location: SourceLocation(filePath: "Sources/Parser/Parser.swift", line: 1, column: 1))
        let parser = TypeDeclaration(
            id: "Parser", name: "Parser", qualifiedName: "Parser", kind: .struct,
            accessLevel: .public, nestedTypes: [parserNode],
            location: SourceLocation(filePath: "Sources/Parser/Parser.swift", line: 1, column: 1))
        let rendererNode = TypeDeclaration(
            id: "Renderer.Node", name: "Node", qualifiedName: "Renderer.Node", kind: .class,
            accessLevel: .public,
            location: SourceLocation(filePath: "Sources/Renderer/Renderer.swift", line: 1, column: 1))
        let renderer = TypeDeclaration(
            id: "Renderer", name: "Renderer", qualifiedName: "Renderer", kind: .struct,
            accessLevel: .public, nestedTypes: [rendererNode],
            location: SourceLocation(filePath: "Sources/Renderer/Renderer.swift", line: 1, column: 1))
        let lexer = TypeDeclaration(
            id: "Lexer", name: "Lexer", qualifiedName: "Lexer", kind: .class, accessLevel: .public,
            inheritedTypes: [TypeReference(name: "Node")],
            location: SourceLocation(filePath: "Sources/Parser/Lexer.swift", line: 1, column: 1))
        let canvas = TypeDeclaration(
            id: "Canvas", name: "Canvas", qualifiedName: "Canvas", kind: .class, accessLevel: .public,
            inheritedTypes: [TypeReference(name: "Node")],
            location: SourceLocation(filePath: "Sources/Renderer/Canvas.swift", line: 1, column: 1))
        let appUser = TypeDeclaration(
            id: "AppUser", name: "AppUser", qualifiedName: "AppUser", kind: .class, accessLevel: .public,
            inheritedTypes: [TypeReference(name: "Node")],
            location: SourceLocation(filePath: "Sources/App/AppUser.swift", line: 1, column: 1))
        return artifact([parser, renderer, lexer, canvas, appUser])
    }

    @Test func sameModuleSimpleNameResolvesDespiteCrossModuleAmbiguity() {
        let resolved = moduleScopedNodeFixture().resolvingRelationshipNames()

        let resolvedLexer = resolved.types.first { $0.name == "Lexer" }
        #expect(resolvedLexer?.inheritedTypes.first?.name == "Parser.Node")
        let resolvedCanvas = resolved.types.first { $0.name == "Canvas" }
        #expect(resolvedCanvas?.inheritedTypes.first?.name == "Renderer.Node")

        // A reference from outside both modules still can't tell which "Node" is meant.
        let appUser = resolved.types.first { $0.name == "AppUser" }
        #expect(appUser?.inheritedTypes.first?.name == "Node")
        let diagnostics = resolved.metadata.parseDiagnostics.filter { $0.kind == .unresolvedReference }
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.message.contains("AppUser") == true)
    }
}
