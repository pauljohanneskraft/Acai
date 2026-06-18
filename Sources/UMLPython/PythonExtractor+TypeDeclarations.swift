import UMLCore
import UMLTreeSitter

// MARK: - Class extraction

extension PythonExtractor {

    /// Base names that mark a class as an enumeration.
    private static let enumBaseNames: Set<String> = [
        "Enum", "IntEnum", "IntFlag", "Flag", "StrEnum", "ReprEnum"
    ]
    /// Base names that mark a class as abstract (in addition to any `@abstractmethod` member).
    private static let abstractBaseNames: Set<String> = ["ABC", "ABCMeta"]
    /// Stdlib "marker" bases that convey kind/abstractness rather than a real supertype. They are
    /// reflected in the `TypeKind`/`.abstract` modifier instead of drawn as inheritance edges, so
    /// a Python `class C(Enum)` / `class P(Protocol)` reads like the other languages' native enum
    /// and interface (no phantom `Enum`/`Protocol`/`ABC` external nodes).
    private static let markerBaseNames: Set<String> =
        enumBaseNames.union(abstractBaseNames).union(["Protocol", "Generic"])

    mutating func extractClass(_ node: Node, decorators: [String]) -> TypeDeclaration {
        let name = node.child(byFieldName: "name").map { text($0) } ?? "_Anonymous"
        let bases = extractBases(node, className: name)
        let kind = classKind(forBaseNames: bases.allNames)

        var generics = bases.generics
        generics.append(contentsOf: extractDeclaredTypeParameters(node))

        var decl = TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: kind,
            accessLevel: accessLevel(forName: name),
            genericParameters: generics,
            inheritedTypes: bases.inherited,
            annotations: decorators,
            location: loc(node)
        )

        if let body = node.child(byFieldName: "body") {
            if kind == .enum {
                parseEnumBody(body, into: &decl)
            } else {
                parseClassBody(body, into: &decl)
            }
        }

        let hasAbstractMember = decl.members.contains { $0.modifiers.contains(.abstract) }
        if hasAbstractMember || bases.allNames.contains(where: { Self.abstractBaseNames.contains($0) }) {
            if !decl.modifiers.contains(.abstract) { decl.modifiers.append(.abstract) }
        }
        return decl
    }

    private func classKind(forBaseNames names: [String]) -> TypeKind {
        if names.contains(where: { Self.enumBaseNames.contains($0) }) { return .enum }
        if names.contains("Protocol") { return .protocol }
        return .class
    }

    // MARK: - Base classes

    /// Extracts positional base classes. `allNames` is every positional base (for kind/abstract
    /// detection); `inherited`/heritage relationships exclude the stdlib markers; `generics` are
    /// pulled from `Generic[T]` / `Protocol[T]` bases. Keyword arguments (`metaclass=…`) are skipped.
    private mutating func extractBases(
        _ classNode: Node, className: String
    ) -> (allNames: [String], inherited: [TypeReference], generics: [GenericParameter]) {
        guard let supers = classNode.child(byFieldName: "superclasses") else { return ([], [], []) }
        var allNames: [String] = []
        var inherited: [TypeReference] = []
        var generics: [GenericParameter] = []

        for child in supers.namedChildren() {
            guard child.nodeType != "keyword_argument" else { continue }

            if child.nodeType == "subscript",
               let valueName = child.child(byFieldName: "value").flatMap({ baseTypeName(from: $0) }),
               valueName == "Generic" || valueName == "Protocol" {
                allNames.append(valueName)
                generics.append(contentsOf: genericParameters(fromSubscript: child))
                continue
            }

            guard let name = baseTypeName(from: child) else { continue }
            allNames.append(name)
            guard !Self.markerBaseNames.contains(name) else { continue }
            inherited.append(TypeReference(name: name))
            relationships.append(Relationship(kind: .inheritance, source: className, target: name))
        }
        return (allNames, inherited, generics)
    }

    /// The simple type name of a base-class expression (`identifier`, `module.Base` → `Base`,
    /// `Base[T]` → `Base`).
    func baseTypeName(from node: Node) -> String? {
        switch node.nodeType {
        case "identifier":
            return text(node)
        case "attribute":
            return node.child(byFieldName: "attribute").map { text($0) }
        case "subscript":
            return node.child(byFieldName: "value").flatMap { baseTypeName(from: $0) }
        case "generic_type":
            return node.namedChildren().first { $0.nodeType == "identifier" }.map { text($0) }
        default:
            return nil
        }
    }

    private func genericParameters(fromSubscript node: Node) -> [GenericParameter] {
        // namedChildren = [value, arg1, arg2, …]; drop the value (e.g. `Generic`) and keep the
        // bracketed type variables.
        node.namedChildren().dropFirst().compactMap { child in
            child.nodeType == "identifier" ? GenericParameter(name: text(child)) : nil
        }
    }

    /// PEP 695 declared type parameters (`class Foo[T]:`), when present.
    private func extractDeclaredTypeParameters(_ node: Node) -> [GenericParameter] {
        guard let params = node.child(byFieldName: "type_parameters") else { return [] }
        return params.namedChildren().compactMap { child in
            let name = child.namedChildren().first { $0.nodeType == "identifier" }.map { text($0) }
                ?? text(child).trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : GenericParameter(name: name)
        }
    }

    // MARK: - Enum body

    /// For enum classes, class-body `NAME = value` assignments are enum cases (not properties);
    /// methods are still extracted as members.
    private mutating func parseEnumBody(_ body: Node, into decl: inout TypeDeclaration) {
        let scope = CallSiteScope(knownTypeNames: collectKnownTypeNames())
        for child in body.namedChildren() {
            switch child.nodeType {
            case "expression_statement":
                for assign in child.namedChildren() where assign.nodeType == "assignment" {
                    guard let left = assign.child(byFieldName: "left"), left.nodeType == "identifier" else { continue }
                    let rawValue = assign.child(byFieldName: "right").map { text($0) }
                    decl.enumCases.append(EnumCase(name: text(left), rawValue: rawValue, location: loc(assign)))
                }
            case "function_definition":
                decl.members.append(extractCallable(child, decorators: [], scope: scope))
            case "decorated_definition":
                if let def = child.child(byFieldName: "definition"), def.nodeType == "function_definition" {
                    decl.members.append(extractCallable(def, decorators: extractDecorators(child), scope: scope))
                }
            default:
                break
            }
        }
    }
}
