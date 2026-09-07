import AcaiCore
import AcaiTreeSitter

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
                extractTopLevelDeclaration(child)
            case "import_or_export", "part_directive", "part_of_directive":
                break
            default:
                if !processTopLevelTypeNode(child, nodeType: nodeType) {
                    extractTopLevelChildren(child)
                }
            }
        }
    }

    private mutating func extractTopLevelChildren(_ node: Node) {
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            processTopLevelTypeNode(child, nodeType: nodeType)
        }
    }

    /// Handles a top-level `declaration` node: `[modifiers] [type] [nullable_type?]
    /// (initialized_identifier_list | static_final_declaration_list)` — the same shape
    /// `extractClassMemberDeclaration` handles inside a class body.
    private mutating func extractTopLevelDeclaration(_ node: Node) {
        let info = collectDeclarationInfo(node)
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            if nodeType == "initialized_identifier_list" {
                globalVariables.append(contentsOf: extractFieldsFromIdentifierList(child, info: info))
            } else if nodeType == "static_final_declaration_list" {
                globalVariables.append(contentsOf: extractStaticFinalFields(child, info: info))
            } else {
                processTopLevelTypeNode(child, nodeType: nodeType)
            }
        }
    }

    // MARK: - Library Name

    private func extractLibraryName(_ node: Node) -> String? {
        let children = node.namedChildren()
        return children.first.map { text($0) }
    }
}
