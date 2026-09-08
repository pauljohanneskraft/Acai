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

    /// A top-level `const`/`final`/typed-or-inferred `var` declaration has no wrapping
    /// `declaration` node the way a class-body field does — the grammar's file-scope rule is
    /// hidden (`_top_level_definition`), so its modifiers, type and `initialized_identifier_list`/
    /// `static_final_declaration_list` all surface as direct, flattened children of the file root
    /// instead. `walkSourceFile` folds each modifier/type child into `pendingGlobalInfo` as it
    /// walks past it and consumes that info the moment it reaches the list node that ends the
    /// declaration, exactly the values `collectDeclarationInfo` would have produced had there been
    /// a node to call it on.
    mutating func walkSourceFile(_ node: Node) {
        var pendingGlobalInfo = DeclarationInfo()
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "library_name":
                currentNamespace = extractLibraryName(child)
            case "import_or_export", "part_directive", "part_of_directive":
                break
            case "initialized_identifier_list":
                globalVariables.append(contentsOf:
                    extractFieldsFromIdentifierList(child, info: resolvingNullableType(pendingGlobalInfo)))
                pendingGlobalInfo = DeclarationInfo()
            case "static_final_declaration_list":
                globalVariables.append(contentsOf:
                    extractStaticFinalFields(child, info: resolvingNullableType(pendingGlobalInfo)))
                pendingGlobalInfo = DeclarationInfo()
            case "final_builtin", "const_builtin", "type_identifier", "generic_type",
                 "function_type", "void_type", "type_arguments", "nullable_type", "inferred_type":
                applyDeclarationChild(child, nodeType: nodeType, to: &pendingGlobalInfo)
            default:
                if !child.isNamed, text(child) == "late" {
                    pendingGlobalInfo.isLate = true
                } else if processTopLevelTypeNode(child, nodeType: nodeType) {
                    pendingGlobalInfo = DeclarationInfo()
                } else {
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

    // MARK: - Library Name

    private func extractLibraryName(_ node: Node) -> String? {
        let children = node.namedChildren()
        return children.first.map { text($0) }
    }
}
