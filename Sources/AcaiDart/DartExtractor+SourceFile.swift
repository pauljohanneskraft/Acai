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
            declarations.types.append(typeDecl)
            return true
        }
        if nodeType == "function_signature",
           let function = memberExtractor.functionSignature(child) {
            declarations.freestandingFunctions.append(function)
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
    /// declaration, exactly the values `declarationInfo(_:)` would have produced had there been
    /// a node to call it on.
    mutating func walkSourceFile(_ node: Node) {
        var pendingGlobalInfo = DartTypeReferenceResolver.DeclarationInfo()
        // Tracks the just-appended top-level function's index so a directly-following
        // `function_body` sibling (its `async`/`async*`/`sync*` marker) can be applied to it.
        var pendingFunctionIndex: Int?
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            if nodeType == "function_body" {
                attachAsyncModifier(to: pendingFunctionIndex, ifBodyIsAsync: child)
                pendingFunctionIndex = nil
                continue
            }
            pendingFunctionIndex = nil
            switch nodeType {
            case "library_name":
                // The library name is the file's namespace for every declaration after it, so it is
                // entered once and never left.
                if let libraryName = extractLibraryName(child) {
                    _ = declarations.enter(namespace: libraryName)
                }
            case "import_or_export", "part_directive", "part_of_directive":
                break
            case "initialized_identifier_list":
                declarations.globalVariables.append(contentsOf:
                    extractFieldsFromIdentifierList(child, info: pendingGlobalInfo.resolvingNullableType()))
                pendingGlobalInfo = DartTypeReferenceResolver.DeclarationInfo()
            case "static_final_declaration_list":
                declarations.globalVariables.append(contentsOf:
                    extractStaticFinalFields(child, info: pendingGlobalInfo.resolvingNullableType()))
                pendingGlobalInfo = DartTypeReferenceResolver.DeclarationInfo()
            case "final_builtin", "const_builtin", "type_identifier", "generic_type",
                 "function_type", "void_type", "type_arguments", "nullable_type", "inferred_type":
                typeReferences.apply(child, nodeType: nodeType, to: &pendingGlobalInfo)
            default:
                pendingFunctionIndex = processTopLevelDefaultChild(
                    child, nodeType: nodeType, pendingGlobalInfo: &pendingGlobalInfo
                )
            }
        }
    }

    private mutating func attachAsyncModifier(to functionIndex: Int?, ifBodyIsAsync node: Node) {
        guard let index = functionIndex, isAsyncFunctionBody(node) else { return }
        declarations.freestandingFunctions[index].modifiers.append(.async)
    }

    /// Handles a top-level child that is neither a directive, a global-variable piece, nor a
    /// declaration-info modifier: a type/function declaration, the `late` keyword, or a nested
    /// wrapper to recurse into. Returns the appended function's index, for a directly-following
    /// `function_body` sibling to apply its `async` marker to.
    private mutating func processTopLevelDefaultChild(
        _ child: Node, nodeType: String, pendingGlobalInfo: inout DartTypeReferenceResolver.DeclarationInfo
    ) -> Int? {
        if !child.isNamed, child.text(in: context) == "late" {
            pendingGlobalInfo.isLate = true
            return nil
        }
        guard processTopLevelTypeNode(child, nodeType: nodeType) else {
            extractTopLevelChildren(child)
            return nil
        }
        pendingGlobalInfo = DartTypeReferenceResolver.DeclarationInfo()
        return nodeType == "function_signature" ? declarations.freestandingFunctions.count - 1 : nil
    }

    private mutating func extractTopLevelChildren(_ node: Node) {
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            processTopLevelTypeNode(child, nodeType: nodeType)
        }
    }

    // MARK: - Library Name

    private func extractLibraryName(_ node: Node) -> String? {
        node.namedChildren().first.map { $0.text(in: context) }
    }
}
