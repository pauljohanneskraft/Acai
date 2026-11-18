import Testing
@testable import AcaiDart
@testable import AcaiCore

@Suite("Dart: Type Alias Tests")
struct DartTypeAliasTests {
    let parser = DartCodeParser()

    @Test func functionTypeAlias() throws {
        let artifact = parser.parse(source: """
        typedef Callback = void Function(Result result);
        """, fileName: "Callback.dart")
        #expect(artifact.types.count == 1)
        let alias = try #require(artifact.types.first)
        #expect(alias.name == "Callback")
        #expect(alias.kind == .typeAlias)
        #expect(alias.accessLevel == .public)
        #expect(alias.inheritedTypes.map(\.name) == ["void Function(Result result)"])
    }

    @Test func genericTypeAliasKeepsTargetArguments() throws {
        let artifact = parser.parse(source: """
        typedef Pair<T> = Map<T, T>;
        """, fileName: "Pair.dart")
        let alias = try #require(artifact.types.first)
        #expect(alias.name == "Pair")
        #expect(alias.kind == .typeAlias)
        #expect(alias.genericParameters.map(\.name) == ["T"])
        let target = try #require(alias.inheritedTypes.first)
        #expect(alias.inheritedTypes.count == 1)
        #expect(target.name == "Map")
        #expect(target.genericArguments.map(\.name) == ["T", "T"])
    }

    @Test func typeAliasWithBoundedParameter() throws {
        let artifact = parser.parse(source: """
        typedef Validator<T extends Comparable<T>> = bool Function(T value);
        """, fileName: "Validator.dart")
        let alias = try #require(artifact.types.first)
        #expect(alias.name == "Validator")
        let parameter = try #require(alias.genericParameters.first)
        let bound = try #require(parameter.constraints.first)
        #expect(alias.genericParameters.count == 1)
        #expect(bound.type.name == "Comparable")
        #expect(bound.type.genericArguments.map(\.name) == ["T"])
        #expect(alias.inheritedTypes.map(\.name) == ["bool Function(T value)"])
    }

    /// The legacy form has no `=`, so its leading identifier is the return type, not the name.
    @Test func legacyFunctionTypedefNamesTheAliasNotItsReturnType() {
        let artifact = parser.parse(source: """
        typedef Result Maker(int count);
        typedef void Notify(Result result);
        """, fileName: "legacy.dart")
        #expect(artifact.types.map(\.name) == ["Maker", "Notify"])
        #expect(artifact.types.allSatisfy { $0.kind == .typeAlias })
    }

    @Test func privateTypeAlias() throws {
        let artifact = parser.parse(source: """
        typedef _Internal = Map<String, Store>;
        """, fileName: "internal.dart")
        let alias = try #require(artifact.types.first)
        #expect(alias.name == "_Internal")
        #expect(alias.accessLevel == .private)
    }
}
