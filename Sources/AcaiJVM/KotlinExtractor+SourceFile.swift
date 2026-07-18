import AcaiCore
import AcaiTreeSitter

// MARK: - Source File & Modifiers

extension KotlinExtractor {

    // MARK: - Source File

    /// Actions for top-level source-file child nodes.
    private enum SourceFileAction {
        case setPackage
        case classDeclaration
        case objectDeclaration
        case functionDeclaration
        case typeAlias
    }

    /// Dispatch table mapping source-file child node types to actions.
    private static let sourceFileDispatch: [String: SourceFileAction] = [
        "package_header": .setPackage,
        "class_declaration": .classDeclaration,
        "object_declaration": .objectDeclaration,
        "function_declaration": .functionDeclaration,
        "type_alias": .typeAlias
    ]

    mutating func walkSourceFile(_ node: Node) {
        for (child, action) in NodeDispatch(Self.sourceFileDispatch).matches(in: node) {
            performSourceFileAction(action, on: child)
        }
    }

    /// Executes the action associated with a source-file child node.
    private mutating func performSourceFileAction(_ action: SourceFileAction, on node: Node) {
        switch action {
        case .setPackage:
            currentNamespace = node
                .firstChild(withType: "identifier")
                .map { text($0) }
        case .classDeclaration:
            handleClassDeclaration(node)
        case .objectDeclaration:
            if let typeDecl = extractObjectDeclaration(node) {
                types.append(typeDecl)
            }
        case .functionDeclaration:
            freestandingFunctions.append(
                extractFunctionDeclaration(node)
            )
        case .typeAlias:
            if let typeDecl = extractTypeAlias(node) {
                types.append(typeDecl)
            }
        }
    }

    private mutating func handleClassDeclaration(_ child: Node) {
        if child.hasDirectChildText("interface", in: context) {
            if let typeDecl = extractInterfaceDeclaration(child) {
                types.append(typeDecl)
            }
        } else {
            if let typeDecl = extractClassDeclaration(child) {
                types.append(typeDecl)
            }
        }
    }

    // MARK: - Modifiers

    // Lookup tables for modifier extraction.
    private static let visibilityMap: [String: AccessLevel] = [
        "public": .public, "private": .private,
        "protected": .protected, "internal": .internal
    ]

    /// Unified modifier map keyed by node type, then by keyword text.
    private static let modifierMapByNodeType: [String: [String: Modifier]] = [
        "class_modifier": [
            "data": .data, "sealed": .sealed, "abstract": .abstract,
            "inner": .inner, "value": .inline
        ],
        "member_modifier": [
            "override": .override, "lateinit": .lazy, "const": .const
        ],
        "property_modifier": [
            "const": .const
        ],
        "function_modifier": [
            "suspend": .suspend, "inline": .inline
        ],
        "inheritance_modifier": [
            "open": .open, "final": .final, "abstract": .abstract
        ]
    ]

    /// Extracts modifier information from a `modifiers` node.
    ///
    /// In Kotlin every declaration without an explicit visibility modifier
    /// is **public** by default, so the returned `accessLevel`
    /// falls back to `.public`.
    func extractModifiers(
        _ node: Node?
    ) -> ModifierInfo {
        guard let node, node.nodeType == "modifiers" else {
            return ModifierInfo(
                accessLevel: .public, modifiers: [], annotations: []
            )
        }
        var access: AccessLevel?
        var modifiers: [Modifier] = []
        var annotations: [String] = []

        for child in node.namedChildren() {
            guard let childType = child.nodeType else { continue }
            let modifierText = text(child)
            if childType == "visibility_modifier" {
                access = Self.visibilityMap[modifierText]
            } else if childType == "annotation" {
                annotations.append(normalizedAnnotation(modifierText))
            } else if let categoryMap = Self.modifierMapByNodeType[childType],
                      let modifier = categoryMap[modifierText] {
                modifiers.append(modifier)
            }
        }
        return ModifierInfo(
            accessLevel: access ?? .public,
            modifiers: modifiers,
            annotations: annotations
        )
    }
}
