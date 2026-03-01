import UMLCore
import UMLTreeSitter

// MARK: - Program & Top-Level Extraction

extension DartExtractor {

    private mutating func extractTopLevelType(
        _ child: Node, nodeType: String
    ) -> TypeDeclaration? {
        switch nodeType {
        case "class_definition":
            return extractClassDefinition(child)
        case "enum_declaration":
            return extractEnumDeclaration(child)
        case "mixin_declaration":
            return extractMixinDeclaration(child)
        case "extension_declaration":
            return extractExtensionDeclaration(child)
        case "extension_type_declaration":
            return extractExtensionTypeDeclaration(child)
        default:
            return nil
        }
    }

    @discardableResult
    private mutating func processTopLevelTypeNode(_ child: Node, nodeType: String) -> Bool {
        if let typeDecl = extractTopLevelType(child, nodeType: nodeType) {
            types.append(typeDecl)
            return true
        }
        if nodeType == "function_signature",
           let function = extractFunctionSignature(child) {
            freestandingFunctions.append(function)
            return true
        }
        return false
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
