import AcaiCore
import AcaiTreeSitter

// MARK: - Class extraction

extension PythonExtractor {

    mutating func extractClass(_ node: Node, decorators: [String]) -> TypeDeclaration {
        let name = node.child(byFieldName: "name").map { text($0) } ?? "_Anonymous"
        // Namespaced so a nested `Inner` doesn't collide with a top-level `Inner`.
        let qualified = declarations.qualifiedName(name)
        let resolver = baseClassResolver
        let bases = resolver.bases(for: node, className: qualified)
        relationships.append(contentsOf: bases.relationships)
        let kind = resolver.kind(forBaseNames: bases.allNames)

        var generics = bases.generics
        generics.append(contentsOf: resolver.declaredTypeParameters(node))

        var decl = TypeDeclaration(
            id: qualified, name: name, qualifiedName: qualified, kind: kind,
            accessLevel: accessLevel(forName: name),
            genericParameters: generics,
            inheritedTypes: bases.inherited,
            annotations: decorators,
            location: loc(node)
        )

        if let body = node.child(byFieldName: "body") {
            let savedNamespace = currentNamespace
            currentNamespace = qualified
            defer { currentNamespace = savedNamespace }
            if kind == .enum {
                parseEnumBody(body, into: &decl)
            } else {
                parseClassBody(body, into: &decl)
            }
        }

        let hasAbstractMember = decl.members.contains { $0.modifiers.contains(.abstract) }
        if hasAbstractMember || resolver.hasAbstractBase(in: bases.allNames) {
            if !decl.modifiers.contains(.abstract) { decl.modifiers.append(.abstract) }
        }
        return decl
    }

    // MARK: - Enum body

    /// Class-body `NAME = value` assignments are enum cases here, not properties.
    private mutating func parseEnumBody(_ body: Node, into decl: inout TypeDeclaration) {
        let scope = CallSiteScope(knownTypeNames: declaredTypeNames)
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
