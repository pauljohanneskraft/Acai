import Testing
@testable import AcaiDart
@testable import AcaiCore

@Suite("Dart: Type Alias Tests")
struct DartTypeAliasTests {
    let parser = DartCodeParser()

    /// `typedef` was dropped entirely, so an aliased callback never reached the diagram.
    @Test func functionTypeAlias() {
        let artifact = parser.parse(source: """
        typedef Callback = void Function(Result result);
        """, fileName: "Callback.dart")
        #expect(artifact.types.count == 1)
        let alias = artifact.types[0]
        #expect(alias.name == "Callback")
        #expect(alias.kind == .typeAlias)
        #expect(alias.accessLevel == .public)
        #expect(alias.inheritedTypes.map(\.name) == ["void Function(Result result)"])
    }

    /// A target built only from type nodes resolves structurally, so the alias carries a real
    /// reference — `Map` with its arguments, not one opaque string — and drives a dependency edge.
    @Test func genericTypeAliasKeepsTargetArguments() {
        let artifact = parser.parse(source: """
        typedef Pair<T> = Map<T, T>;
        """, fileName: "Pair.dart")
        let alias = artifact.types[0]
        #expect(alias.name == "Pair")
        #expect(alias.kind == .typeAlias)
        #expect(alias.genericParameters.map(\.name) == ["T"])
        #expect(alias.inheritedTypes.count == 1)
        #expect(alias.inheritedTypes[0].name == "Map")
        #expect(alias.inheritedTypes[0].genericArguments.map(\.name) == ["T", "T"])
    }

    /// An alias may itself be generic and bounded; the bound belongs to the alias, not the target.
    @Test func typeAliasWithBoundedParameter() {
        let artifact = parser.parse(source: """
        typedef Validator<T extends Comparable<T>> = bool Function(T value);
        """, fileName: "Validator.dart")
        let alias = artifact.types[0]
        #expect(alias.name == "Validator")
        #expect(alias.genericParameters.count == 1)
        #expect(alias.genericParameters[0].constraints[0].type.name == "Comparable")
        #expect(alias.genericParameters[0].constraints[0].type.genericArguments.map(\.name) == ["T"])
        #expect(alias.inheritedTypes.map(\.name) == ["bool Function(T value)"])
    }

    /// Dart's older `typedef <return> <name>(<params>)` form carries no `=`, so the name is the
    /// identifier holding the parameter list and the return type in front of it is part of the
    /// target. Read left to right, the name would come out as the return type instead.
    @Test func legacyFunctionTypedefNamesTheAliasNotItsReturnType() {
        let artifact = parser.parse(source: """
        typedef Result Maker(int count);
        typedef void Notify(Result result);
        """, fileName: "legacy.dart")
        #expect(artifact.types.map(\.name) == ["Maker", "Notify"])
        #expect(artifact.types.allSatisfy { $0.kind == .typeAlias })
    }

    /// A leading underscore is Dart's library-private marker, and an alias is named like any other
    /// declaration.
    @Test func privateTypeAlias() {
        let artifact = parser.parse(source: """
        typedef _Internal = Map<String, Store>;
        """, fileName: "internal.dart")
        #expect(artifact.types[0].name == "_Internal")
        #expect(artifact.types[0].accessLevel == .private)
    }
}
