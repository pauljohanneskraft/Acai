import AcaiCore
import AcaiTreeSitter

// MARK: - Source File & Modifiers

extension KotlinExtractor {

    // MARK: - Source File

    private enum SourceFileAction {
        case setPackage
        case classDeclaration
        case objectDeclaration
        case functionDeclaration
        case propertyDeclaration
        case typeAlias
    }

    private static let sourceFileDispatch: [String: SourceFileAction] = [
        "package_header": .setPackage,
        "class_declaration": .classDeclaration,
        "object_declaration": .objectDeclaration,
        "function_declaration": .functionDeclaration,
        "property_declaration": .propertyDeclaration,
        "type_alias": .typeAlias
    ]

    mutating func walkSourceFile(_ node: Node) {
        for (child, action) in NodeDispatch(Self.sourceFileDispatch).matches(in: node) {
            performSourceFileAction(action, on: child)
        }
    }

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
        case .propertyDeclaration:
            globalVariables.append(extractPropertyDeclaration(node))
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

    /// In Kotlin every declaration without an explicit visibility modifier is **public** by default,
    /// so the returned `accessLevel` falls back to `.public`.
    private static let modifierClassifier = ModifierClassifier(
        defaultAccessLevel: .public,
        annotationNodeTypes: ["annotation"],
        classify: { nodeType, text in
            if nodeType == "visibility_modifier" { return visibilityMap[text].map { .accessLevel($0) } }
            if let categoryMap = modifierMapByNodeType[nodeType], let modifier = categoryMap[text] {
                return .modifier(modifier)
            }
            return nil
        }
    )

    func extractModifiers(_ node: Node?) -> ModifierInfo {
        Self.modifierClassifier.modifierInfo(for: node, in: context)
    }
}
