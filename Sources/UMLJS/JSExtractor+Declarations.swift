import UMLCore
import UMLTreeSitter

// MARK: - Declaration Dispatch & Extraction

extension JSExtractor {

    // MARK: - Program

    mutating func walkSourceFile(_ node: Node) {
        for child in node.children() {
            visitTopLevelNode(child)
        }
        // In JS mode, detect prototype patterns
        if !isTypeScript {
            detectPrototypePatterns(node)
        }
    }

    // MARK: - Top-Level Dispatch

    private mutating func visitTopLevelNode(_ node: Node) {
        guard let nodeType = node.nodeType else { return }
        if nodeType == "export_statement" {
            visitExportStatement(node)
        } else if nodeType == "expression_statement", isTypeScript {
            // tree-sitter-typescript 0.23+: namespace Foo {} → expression_statement → internal_module
            for inner in node.namedChildren() {
                guard let nodeType = inner.nodeType,
                      nodeType == "internal_module" || nodeType == "module" else { continue }
                let (newTypes, newFunctions) = dispatchDeclaration(inner, isExported: false)
                types += newTypes; freestandingFunctions += newFunctions
            }
        } else {
            let (newTypes, newFunctions) = dispatchDeclaration(node, isExported: false)
            types += newTypes; freestandingFunctions += newFunctions
        }
    }

    // MARK: - Export Statement

    private mutating func visitExportStatement(_ node: Node) {
        let isDefault = node.hasDirectChildText("default", in: context)
        let exportDecorators = extractDecorators(node)
        for child in node.children() {
            let (newTypes, newFunctions) = dispatchDeclaration(child, isExported: true, isDefault: isDefault,
                                              decorators: exportDecorators)
            types += newTypes; freestandingFunctions += newFunctions
        }
    }

    // MARK: - Declaration Dispatch

    /// Shared dispatch for top-level nodes, export children, and module body children.
    @discardableResult
    mutating func dispatchDeclaration(
        _ node: Node,
        isExported: Bool,
        isDefault: Bool = false,
        decorators: [String] = [],
        namespace: String? = nil
    ) -> (types: [TypeDeclaration], functions: [Member]) {
        guard let nodeType = node.nodeType else { return ([], []) }

        if nodeType == "function_declaration" {
            return ([], [extractFunctionDeclaration(node, isExported: isExported)])
        }

        if let typeDecls = dispatchModuleDeclaration(nodeType, node: node, isExported: isExported) {
            return (typeDecls.map { applyMetadata(to: $0, decorators: decorators, namespace: namespace) }, [])
        }

        if let typeDecl = dispatchTypeDeclaration(nodeType, node: node, isExported: isExported, isDefault: isDefault) {
            return ([applyMetadata(to: typeDecl, decorators: decorators, namespace: namespace)], [])
        }

        return ([], [])
    }

    private mutating func dispatchTypeDeclaration(
        _ nodeType: String,
        node: Node,
        isExported: Bool,
        isDefault: Bool
    ) -> TypeDeclaration? {
        switch nodeType {
        case "class_declaration", "class":
            return extractClassLikeDeclaration(node, isExported: isExported, isDefault: isDefault)
        case "abstract_class_declaration" where isTypeScript:
            return extractClassLikeDeclaration(node, isExported: isExported, isDefault: isDefault, isAbstract: true)
        case "interface_declaration" where isTypeScript:
            return extractInterfaceDeclaration(node, isExported: isExported)
        case "type_alias_declaration" where isTypeScript:
            return extractTypeAliasDeclaration(node, isExported: isExported)
        case "enum_declaration" where isTypeScript:
            return extractEnumDeclaration(node, isExported: isExported)
        default:
            return nil
        }
    }

    private mutating func dispatchModuleDeclaration(
        _ nodeType: String,
        node: Node,
        isExported: Bool
    ) -> [TypeDeclaration]? {
        guard isTypeScript, nodeType == "module" || nodeType == "internal_module" else { return nil }
        return extractModule(node, isExported: isExported)
    }

    private func applyMetadata(
        to declaration: TypeDeclaration,
        decorators: [String],
        namespace: String?
    ) -> TypeDeclaration {
        var result = declaration
        result.annotations.append(contentsOf: decorators)
        if let namespace { result.namespace = namespace }
        return result
    }

    // MARK: - Class Declaration

    private mutating func extractClassLikeDeclaration(
        _ node: Node, isExported: Bool, isDefault: Bool, isAbstract: Bool = false
    ) -> TypeDeclaration {
        let nodeLoc = loc(node)
        var name = node.child(byFieldName: "name").map { text($0) } ?? ""
        if name.isEmpty { name = isDefault ? "default" : "_Anonymous" }

        let modifiers: [Modifier] = isAbstract ? [.abstract] : []
        var annotations = extractDecorators(node)
        if isDefault { annotations.append("default") }

        let generics = isTypeScript ? extractTypeParameters(node) : []
        let (inherited, rels) = extractClassHeritage(node, className: name)
        relationships.append(contentsOf: rels)

        var typeDecl = TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .class,
            accessLevel: isExported ? .public : nil,
            modifiers: modifiers,
            genericParameters: generics,
            inheritedTypes: inherited,
            annotations: annotations,
            location: nodeLoc
        )

        if let body = node.child(byFieldName: "body") {
            parseClassBody(body, into: &typeDecl)
        }
        return typeDecl
    }

    // MARK: - Class Heritage (extends/implements)

    private func extractClassHeritage(_ node: Node, className: String) -> ([TypeReference], [Relationship]) {
        var inherited: [TypeReference] = []
        var rels: [Relationship] = []

        for child in node.children() {
            if child.nodeType == "class_heritage" {
                for heritageChild in child.children() {
                    collectHeritageClause(heritageChild, className: className,
                                         inherited: &inherited, rels: &rels)
                }
            }
            collectHeritageClause(child, className: className,
                                 inherited: &inherited, rels: &rels)
        }
        return (inherited, rels)
    }

    private func collectHeritageClause(
        _ node: Node, className: String,
        inherited: inout [TypeReference], rels: inout [Relationship]
    ) {
        switch node.nodeType {
        case "extends_clause":
            if let valueNode = node.child(byFieldName: "value") ?? node.namedChildren().first {
                let ref = extractTypeReferenceFromExpression(valueNode)
                inherited.append(ref)
                rels.append(Relationship(kind: .inheritance, source: className, target: ref.name))
            }
        case "implements_clause":
            for typeNode in node.namedChildren() {
                let ref = extractTypeReferenceFromExpression(typeNode)
                inherited.append(ref)
                rels.append(Relationship(kind: .conformance, source: className, target: ref.name))
            }
        default:
            break
        }
    }

    // MARK: - Decorators / Annotations

    func extractDecorators(_ node: Node) -> [String] {
        var annotations: [String] = []
        for child in node.children() {
            guard child.nodeType == "decorator" else { continue }
            let fullText = text(child)
            if let parenIdx = fullText.firstIndex(of: "(") {
                annotations.append(String(fullText[fullText.startIndex..<parenIdx]))
            } else {
                annotations.append(fullText)
            }
        }
        return annotations
    }
}
