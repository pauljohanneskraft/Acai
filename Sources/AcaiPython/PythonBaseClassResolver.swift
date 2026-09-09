import AcaiCore
import AcaiTreeSitter

// MARK: - PythonBaseClassResolver

/// Resolves a Python class's base-class list into what `extractClass` needs to build the type
/// declaration: the positional base names (for kind/abstract detection), the non-marker bases as
/// inheritance edges, and any `Generic[T]`/`Protocol[T]`/PEP 695 type parameters. Stateless beyond
/// `context`, mirroring `PythonTypeReferenceResolver`.
struct PythonBaseClassResolver {
    let context: SourceFileContext

    private static let enumBaseNames: Set<String> = [
        "Enum", "IntEnum", "IntFlag", "Flag", "StrEnum", "ReprEnum"
    ]
    private static let abstractBaseNames: Set<String> = ["ABC", "ABCMeta"]
    /// Stdlib "marker" bases reflected in `TypeKind`/`.abstract` instead of drawn as inheritance
    /// edges, so `class C(Enum)` reads like other languages' native enum (no phantom `Enum` node).
    private static let markerBaseNames: Set<String> =
        enumBaseNames.union(abstractBaseNames).union(["Protocol", "Generic"])

    struct Bases {
        var allNames: [String] = []
        var inherited: [TypeReference] = []
        var generics: [GenericParameter] = []
        var relationships: [Relationship] = []
    }

    /// `allNames` is every positional base (for kind/abstract detection); `inherited` excludes the
    /// stdlib markers. Keyword arguments (`metaclass=…`) are skipped.
    func bases(for classNode: Node, className: String) -> Bases {
        guard let supers = classNode.child(byFieldName: "superclasses") else { return Bases() }
        var result = Bases()
        let typeReferences = PythonTypeReferenceResolver(context: context)

        for child in supers.namedChildren() {
            guard child.nodeType != "keyword_argument" else { continue }

            if child.nodeType == "subscript",
               let valueName = child.child(byFieldName: "value").flatMap({ typeReferences.baseTypeName(from: $0) }),
               valueName == "Generic" || valueName == "Protocol" {
                result.allNames.append(valueName)
                result.generics.append(contentsOf: genericParameters(fromSubscript: child))
                continue
            }

            guard let name = typeReferences.baseTypeName(from: child) else { continue }
            result.allNames.append(name)
            guard !Self.markerBaseNames.contains(name) else { continue }
            result.inherited.append(TypeReference(name: name))
            result.relationships.append(Relationship(kind: .inheritance, source: className, target: name))
        }
        return result
    }

    func kind(forBaseNames names: [String]) -> TypeKind {
        if names.contains(where: { Self.enumBaseNames.contains($0) }) { return .enum }
        if names.contains("Protocol") { return .protocol }
        return .class
    }

    func hasAbstractBase(in names: [String]) -> Bool {
        names.contains(where: { Self.abstractBaseNames.contains($0) })
    }

    private func genericParameters(fromSubscript node: Node) -> [GenericParameter] {
        // namedChildren = [value, arg1, arg2, …]; drop the value (e.g. `Generic`) and keep the
        // bracketed type variables.
        node.namedChildren().dropFirst().compactMap { child in
            child.nodeType == "identifier" ? GenericParameter(name: child.text(in: context)) : nil
        }
    }

    /// PEP 695 declared type parameters (`class Foo[T]:`), when present.
    func declaredTypeParameters(_ node: Node) -> [GenericParameter] {
        guard let params = node.child(byFieldName: "type_parameters") else { return [] }
        return params.namedChildren().compactMap { child in
            let name = child.namedChildren().first { $0.nodeType == "identifier" }.map { $0.text(in: context) }
                ?? child.text(in: context).trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : GenericParameter(name: name)
        }
    }
}

extension PythonExtractor {
    var baseClassResolver: PythonBaseClassResolver { PythonBaseClassResolver(context: context) }
}
