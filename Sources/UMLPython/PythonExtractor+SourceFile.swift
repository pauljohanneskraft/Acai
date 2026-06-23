import UMLCore
import UMLTreeSitter

// MARK: - Top-level traversal

extension PythonExtractor {

    mutating func walkSourceFile(_ node: Node) {
        for child in node.children() {
            visitTopLevel(child)
        }
    }

    private mutating func visitTopLevel(_ node: Node) {
        switch node.nodeType {
        case "class_definition":
            types.append(extractClass(node, decorators: []))
        case "function_definition":
            freestandingFunctions.append(extractCallable(node, decorators: [], scope: moduleScope()))
        case "decorated_definition":
            visitDecorated(node)
        case "expression_statement":
            for assign in node.namedChildren() where assign.nodeType == "assignment" {
                if let member = extractModuleVariable(assign) {
                    globalVariables.append(member)
                }
            }
        default:
            break
        }
    }

    private mutating func visitDecorated(_ node: Node) {
        let decorators = extractDecorators(node)
        guard let def = node.child(byFieldName: "definition") else { return }
        switch def.nodeType {
        case "class_definition":
            types.append(extractClass(def, decorators: decorators))
        case "function_definition":
            freestandingFunctions.append(extractCallable(def, decorators: decorators, scope: moduleScope()))
        default:
            break
        }
    }

    /// Call-site scope for module-level functions: no instance properties, but declared types are
    /// still resolvable for `TypeName.method()` static calls.
    func moduleScope() -> CallSiteScope {
        CallSiteScope(knownTypeNames: declaredTypeNames)
    }

    /// A module-level `x = …` (optionally annotated `x: T = …`) becomes a global variable.
    func extractModuleVariable(_ assign: Node) -> Member? {
        guard let left = assign.child(byFieldName: "left"), left.nodeType == "identifier" else { return nil }
        let name = text(left)
        let type = assign.child(byFieldName: "type").flatMap { extractType(fromTypeField: $0) }
        let initial = assign.child(byFieldName: "right").map { classifyValue($0) }
        return Member(
            name: name,
            kind: .property,
            accessLevel: accessLevel(forName: name),
            type: type,
            location: loc(assign),
            initialValue: initial
        )
    }

    // MARK: - Decorators

    /// Bare decorator names (without the leading `@` and any call arguments), e.g. `@app.route(...)`
    /// → `"app.route"`, `@dataclass` → `"dataclass"`. Works on either a `decorated_definition`
    /// (whose `decorator` children are read) or any node carrying `decorator` children.
    func extractDecorators(_ node: Node) -> [String] {
        var result: [String] = []
        for child in node.children() where child.nodeType == "decorator" {
            var raw = text(child)
            if raw.hasPrefix("@") { raw.removeFirst() }
            if let paren = raw.firstIndex(of: "(") { raw = String(raw[raw.startIndex..<paren]) }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { result.append(trimmed) }
        }
        return result
    }
}
