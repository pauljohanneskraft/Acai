import UMLCore
import UMLTreeSitter

// MARK: - Program & Top-Level Extraction

extension DartExtractor {

    @discardableResult
    private mutating func processTopLevelTypeNode(_ child: Node, nodeType: String) -> Bool {
        switch nodeType {
        case "class_definition":
            if let typeDecl = extractClassDefinition(child) { types.append(typeDecl) }
        case "enum_declaration":
            if let typeDecl = extractEnumDeclaration(child) { types.append(typeDecl) }
        case "mixin_declaration":
            if let typeDecl = extractMixinDeclaration(child) { types.append(typeDecl) }
        case "extension_declaration":
            if let typeDecl = extractExtensionDeclaration(child) { types.append(typeDecl) }
        case "extension_type_declaration":
            if let typeDecl = extractExtensionTypeDeclaration(child) { types.append(typeDecl) }
        case "function_signature":
            if let function = extractFunctionSignature(child, isTopLevel: true) {
                freestandingFunctions.append(function)
            }
        default:
            return false
        }
        return true
    }

    mutating func walkSourceFile(_ node: Node) {
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "library_name":
                currentNamespace = extractLibraryName(child)
            case "declaration":
                extractTopLevelChildren(child)
            case "import_or_export", "part_directive", "part_of_directive":
                break
            default:
                if !processTopLevelTypeNode(child, nodeType: nodeType) {
                    extractTopLevelChildren(child)
                }
            }
        }
    }

    /// Some top-level constructs may be wrapped in container nodes.
    private mutating func extractTopLevelChildren(_ node: Node) {
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            processTopLevelTypeNode(child, nodeType: nodeType)
        }
    }

    // MARK: - Library Name

    private func extractLibraryName(_ node: Node) -> String? {
        let children = node.namedChildren()
        return children.first.map { text($0) }
    }
}
