import UMLCore
import UMLTreeSitter

struct RubyExtractor: TreeSitterExtracting {
    let context: SourceFileContext

    var types: [TypeDeclaration] = []
    var relationships: [Relationship] = []
    var freestandingFunctions: [Member] = []
    var currentNamespace: String?
    var declaredTypeNames: Set<String> = []

    init(source: String, fileName: String) {
        self.context = SourceFileContext(source: source, fileName: fileName)
    }

    mutating func extract(from root: Node) -> CodeArtifact {
        declaredTypeNames = collectDeclaredTypeNames(
            from: root,
            declarationNodeTypes: ["class", "module"],
            name: { self.typeName(in: $0)?.simple }
        )
        walkSourceFile(root)
        resolveRelationshipNames()
        return buildArtifact(language: .ruby)
    }

    mutating func walkSourceFile(_ node: Node) {
        for child in node.namedChildren() {
            switch child.nodeType {
            case "class":
                if let type = extractType(from: child, kind: .class) {
                    types.append(type)
                }
            case "module":
                if let type = extractType(from: child, kind: .module) {
                    types.append(type)
                }
            case "method":
                if let member = extractMethod(from: child, isStatic: false) {
                    freestandingFunctions.append(member)
                }
            case "singleton_method":
                if let member = extractMethod(from: child, isStatic: true) {
                    freestandingFunctions.append(member)
                }
            default:
                continue
            }
        }
    }

    private mutating func extractType(from node: Node, kind: TypeKind) -> TypeDeclaration? {
        guard let resolvedName = typeName(in: node) else { return nil }

        let parentNamespace = currentNamespace
        let qualifiedName: String
        if let parentNamespace {
            if resolvedName.qualified.hasPrefix("\(parentNamespace).") || resolvedName.qualified == parentNamespace {
                qualifiedName = resolvedName.qualified
            } else {
                qualifiedName = "\(parentNamespace).\(resolvedName.qualified)"
            }
        } else {
            qualifiedName = resolvedName.qualified
        }
        let namespace = qualifiedName.split(separator: ".").dropLast().joined(separator: ".")

        var declaration = TypeDeclaration(
            id: qualifiedName,
            name: resolvedName.simple,
            qualifiedName: qualifiedName,
            kind: kind,
            accessLevel: .public,
            namespace: namespace.isEmpty ? nil : namespace,
            location: loc(node)
        )

        if kind == .class, let superclass = superclassReference(in: node) {
            declaration.inheritedTypes = [superclass]
            relationships.append(Relationship(kind: .inheritance, source: qualifiedName, target: superclass.name))
        }

        currentNamespace = qualifiedName
        if let body = node.child(byFieldName: "body") {
            let bodyExtraction = extractTypeBody(from: body)
            declaration.members = bodyExtraction.members
            declaration.nestedTypes = bodyExtraction.nestedTypes
        }
        currentNamespace = parentNamespace

        return declaration
    }

    private mutating func extractTypeBody(from body: Node) -> (members: [Member], nestedTypes: [TypeDeclaration]) {
        var members: [Member] = []
        var nestedTypes: [TypeDeclaration] = []
        var currentAccessLevel: AccessLevel = .public

        for child in body.namedChildren() {
            switch child.nodeType {
            case "identifier":
                let text = self.text(child)
                if text == "public" { currentAccessLevel = .public }
                else if text == "protected" { currentAccessLevel = .protected }
                else if text == "private" { currentAccessLevel = .private }
            case "call", "method_call":
                guard let methodNode = child.child(byFieldName: "method") else { continue }
                let methodText = self.text(methodNode)
                if methodText == "attr_accessor" || methodText == "attr_reader" || methodText == "attr_writer" {
                    members.append(contentsOf: extractAttribute(from: child, accessLevel: currentAccessLevel))
                } else if methodText == "include" || methodText == "extend" {
                    extractIncludes(from: child)
                }
            case "method":
                if var member = extractMethod(from: child, isStatic: false) {
                    member.accessLevel = currentAccessLevel
                    members.append(member)
                }
            case "singleton_method":
                if var member = extractMethod(from: child, isStatic: true) {
                    member.accessLevel = currentAccessLevel
                    members.append(member)
                }
            case "class":
                if let nested = extractType(from: child, kind: .class) {
                    nestedTypes.append(nested)
                }
            case "module":
                if let nested = extractType(from: child, kind: .module) {
                    nestedTypes.append(nested)
                }
            default:
                continue
            }
        }

        return (members, nestedTypes)
    }

    private mutating func extractAttribute(from node: Node, accessLevel: AccessLevel) -> [Member] {
        guard let argsNode = node.child(byFieldName: "arguments") else { return [] }
        var members: [Member] = []
        for child in argsNode.namedChildren() {
            let rawName = text(child)
            let name = rawName.hasPrefix(":") ? String(rawName.dropFirst()) : rawName
            let member = Member(name: name, kind: .property, accessLevel: accessLevel, location: loc(child))
            members.append(member)
        }
        return members
    }

    private mutating func extractIncludes(from node: Node) {
        guard let argsNode = node.child(byFieldName: "arguments") else { return }
        guard let currentNamespace else { return }
        for child in argsNode.namedChildren() {
            guard let ref = constantPath(from: child) else { continue }
            relationships.append(Relationship(kind: .conformance, source: currentNamespace, target: ref.simple))
        }
    }

    private func extractMethod(from node: Node, isStatic: Bool) -> Member? {
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        let methodName = text(nameNode)

        return Member(
            name: methodName,
            kind: methodName == "initialize" ? .initializer : .method,
            accessLevel: .public,
            modifiers: isStatic ? [.static] : [],
            parameters: methodParameters(in: node),
            location: loc(node)
        )
    }

    private func methodParameters(in methodNode: Node) -> [Parameter] {
        guard let parametersNode = methodNode.child(byFieldName: "parameters") else { return [] }
        var parameters: [Parameter] = []

        for child in parametersNode.namedChildren() {
            switch child.nodeType {
            case "identifier":
                parameters.append(Parameter(internalName: text(child)))
            case "optional_parameter":
                if let nameNode = child.child(byFieldName: "name") {
                    let defaultValue = child.child(byFieldName: "value").map(text)
                    parameters.append(
                        Parameter(
                            internalName: text(nameNode),
                            defaultValue: defaultValue
                        )
                    )
                }
            case "keyword_parameter":
                if let nameNode = child.child(byFieldName: "name") {
                    let defaultValue = child.child(byFieldName: "value").map(text)
                    parameters.append(
                        Parameter(
                            internalName: text(nameNode),
                            defaultValue: defaultValue
                        )
                    )
                }
            case "splat_parameter":
                if let nameNode = child.child(byFieldName: "name") {
                    parameters.append(Parameter(internalName: text(nameNode), isVariadic: true))
                }
            case "hash_splat_parameter":
                if let nameNode = child.child(byFieldName: "name") {
                    parameters.append(Parameter(internalName: text(nameNode), isVariadic: true))
                }
            case "block_parameter":
                if let nameNode = child.child(byFieldName: "name") {
                    parameters.append(Parameter(internalName: text(nameNode)))
                }
            default:
                continue
            }
        }

        return parameters
    }

    private func superclassReference(in node: Node) -> TypeReference? {
        guard let superclassNode = node.child(byFieldName: "superclass") else { return nil }
        let valueNode = superclassNode.namedChildren().first ?? superclassNode
        guard let reference = constantPath(from: valueNode), !reference.simple.isEmpty else { return nil }
        return TypeReference(name: reference.simple)
    }

    private func typeName(in node: Node) -> QualifiedName? {
        guard let nameNode = node.child(byFieldName: "name") else { return nil }
        return constantPath(from: nameNode)
    }

    private func constantPath(from node: Node) -> QualifiedName? {
        switch node.nodeType {
        case "constant":
            let name = text(node)
            return QualifiedName(simple: name, qualified: name)
        case "scope_resolution":
            let scope = node.child(byFieldName: "scope").flatMap { constantPath(from: $0) }
            guard let nameNode = node.child(byFieldName: "name") else { return nil }
            let simple = text(nameNode)
            let qualified: String
            if let scope, !scope.qualified.isEmpty {
                qualified = "\(scope.qualified).\(simple)"
            } else {
                qualified = simple
            }
            return QualifiedName(simple: simple, qualified: qualified)
        default:
            return nil
        }
    }
}

private struct QualifiedName {
    let simple: String
    let qualified: String
}
