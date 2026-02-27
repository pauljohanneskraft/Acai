import UMLCore
import UMLTreeSitter

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
        for child in node.children() {
            guard let nodeType = child.nodeType,
                  let action = Self.sourceFileDispatch[nodeType] else { continue }
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

    // Lookup tables for modifier extraction (reduces cyclomatic complexity).
    private static let visibilityMap: [String: AccessLevel] = [
        "public": .public, "private": .private,
        "protected": .protected, "internal": .internal
    ]
    private static let classModifierMap: [String: Modifier] = [
        "data": .data, "sealed": .sealed, "abstract": .abstract,
        "inner": .inner, "value": .inline
    ]
    private static let memberModifierMap: [String: Modifier] = [
        "override": .override, "lateinit": .lazy, "const": .const
    ]
    private static let functionModifierMap: [String: Modifier] = [
        "suspend": .suspend, "inline": .inline
    ]
    private static let inheritanceModifierMap: [String: Modifier] = [
        "open": .open, "final": .final, "abstract": .abstract
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
            let modifierText = text(child)
            switch child.nodeType {
            case "visibility_modifier":
                access = Self.visibilityMap[modifierText]
            case "class_modifier":
                Self.classModifierMap[modifierText].map { modifiers.append($0) }
            case "member_modifier":
                Self.memberModifierMap[modifierText].map { modifiers.append($0) }
            case "property_modifier":
                if modifierText == "const" { modifiers.append(.const) }
            case "function_modifier":
                Self.functionModifierMap[modifierText].map { modifiers.append($0) }
            case "inheritance_modifier":
                Self.inheritanceModifierMap[modifierText].map { modifiers.append($0) }
            case "annotation":
                annotations.append(
                    modifierText.hasPrefix("@") ? modifierText : "@\(modifierText)"
                )
            default:
                break
            }
        }
        return ModifierInfo(
            accessLevel: access ?? .public,
            modifiers: modifiers,
            annotations: annotations
        )
    }
}
