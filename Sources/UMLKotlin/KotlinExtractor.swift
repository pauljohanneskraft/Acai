import UMLCore
import UMLTreeSitter

/// Extracts type declarations, relationships, and freestanding functions
/// from a Kotlin source file's tree-sitter AST.
final class KotlinExtractor: TreeSitterExtracting, CallSiteResolving {

    // MARK: - State

    let context: SourceFileContext
    var types: [TypeDeclaration] = []
    var relationships: [Relationship] = []
    var freestandingFunctions: [Member] = []
    var currentNamespace: String?

    init(source: String, fileName: String) {
        self.context = SourceFileContext(source: source, fileName: fileName)
    }

    // MARK: - Public Entry Point

    func extract(from root: Node) -> CodeArtifact {
        walkSourceFile(root)
        resolveRelationshipNames()
        return buildArtifact(language: .kotlin)
    }

    // MARK: - Kotlin-Specific Helpers

    /// Shorthand for ``hasAnonymousKeyword(_:in:)``.
    func hasKeyword(_ keyword: String, in node: Node) -> Bool {
        hasAnonymousKeyword(keyword, in: node)
    }

    /// Returns whether the node declares `val` or `var` via a `binding_pattern_kind` child.
    /// Tree-sitter-kotlin wraps `val`/`var` in `[binding_pattern_kind] → [val]`.
    private func bindingKind(of node: Node) -> String? {
        guard let bindingPatternNode = node.firstChild(withType: "binding_pattern_kind") else { return nil }
        let bindingText = text(bindingPatternNode).trimmingCharacters(in: .whitespaces)
        return (bindingText == "val" || bindingText == "var") ? bindingText : nil
    }
}

// MARK: - Source File & Modifiers

extension KotlinExtractor {

    // MARK: - Source File

    func walkSourceFile(_ node: Node) {
        for child in node.children() {
            guard let nodeType = child.nodeType else { continue }
            switch nodeType {
            case "package_header":
                currentNamespace = child
                    .firstChild(withType: "identifier")
                    .map { text($0) }
            case "import_list", "import_header":
                break
            case "class_declaration":
                handleClassDeclaration(child)
            case "object_declaration":
                if let typeDecl = extractObjectDeclaration(child) {
                    types.append(typeDecl)
                }
            case "function_declaration":
                freestandingFunctions.append(
                    extractFunctionDeclaration(child)
                )
            case "type_alias":
                if let typeDecl = extractTypeAlias(child) {
                    types.append(typeDecl)
                }
            default:
                break
            }
        }
    }

    private func handleClassDeclaration(_ child: Node) {
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
    private func extractModifiers(
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

    // MARK: - Class Declaration

    private func extractClassDeclaration(_ node: Node) -> TypeDeclaration? {
        let modifierInfo = extractModifiers(node.firstChild(withType: "modifiers"))

        if node.hasChild(withType: "enum_class_body") {
            return extractEnumClassDeclaration(node, modifierInfo: modifierInfo)
        }

        guard let nameNode = node.firstChild(withType: "type_identifier") else { return nil }
        let name = text(nameNode)
        let qualifiedTypeName = qualifiedName(name)

        let generics = extractTypeParameters(node.firstChild(withType: "type_parameters"))
        let ctorNode = node.firstChild(withType: "primary_constructor")
        let ctorAccess = ctorNode
            .flatMap { $0.firstChild(withType: "modifiers") }
            .map { extractModifiers($0).accessLevel } ?? modifierInfo.accessLevel
        let ctorParams = extractPrimaryConstructorParams(ctorNode)
        let supertypes = classifySupertypes(node.allChildren(withType: "delegation_specifier"))

        let isAnnotation = node.firstChild(withType: "modifiers")?.namedChildren()
            .contains { $0.nodeType == "class_modifier" && text($0) == "annotation" } ?? false

        var typeDecl = TypeDeclaration(
            id: qualifiedTypeName, name: name, qualifiedName: qualifiedTypeName,
            kind: isAnnotation ? .annotation : .class,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            genericParameters: generics, inheritedTypes: supertypes.map(\.typeRef),
            annotations: modifierInfo.annotations, namespace: currentNamespace, location: loc(node)
        )

        // Promoted constructor properties — each carries its own access level.
        for constructorParam in ctorParams where constructorParam.isProperty {
            var modifiers = constructorParam.modifiers
            if constructorParam.isReadOnly { modifiers.append(.readonly) }
            typeDecl.members.append(Member(
                name: constructorParam.parameter.internalName, kind: .property,
                accessLevel: constructorParam.accessLevel, modifiers: modifiers,
                type: constructorParam.parameter.type, annotations: constructorParam.annotations
            ))
        }
        if !ctorParams.isEmpty {
            typeDecl.members.append(Member(
                name: "init", kind: .initializer,
                accessLevel: ctorAccess,
                parameters: ctorParams.map(\.parameter)
            ))
        }

        for supertype in supertypes {
            relationships.append(Relationship(
                kind: supertype.isClassInheritance ? .inheritance : .conformance,
                source: qualifiedTypeName, target: supertype.typeRef.name))
        }
        if let body = node.firstChild(withType: "class_body") {
            extractBody(body, into: &typeDecl)
        }
        return typeDecl
    }

    // MARK: - Interface

    private func extractInterfaceDeclaration(_ node: Node) -> TypeDeclaration? {
        let modifierInfo = extractModifiers(node.firstChild(withType: "modifiers"))
        guard let nameNode = node.firstChild(withType: "type_identifier") else { return nil }
        let name = text(nameNode)
        let qualifiedTypeName = qualifiedName(name)

        let generics = extractTypeParameters(node.firstChild(withType: "type_parameters"))
        let supertypes = classifySupertypes(node.allChildren(withType: "delegation_specifier"))

        var typeDecl = TypeDeclaration(
            id: qualifiedTypeName, name: name, qualifiedName: qualifiedTypeName, kind: .interface,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            genericParameters: generics, inheritedTypes: supertypes.map(\.typeRef),
            annotations: modifierInfo.annotations, namespace: currentNamespace, location: loc(node)
        )
        for supertype in supertypes {
            relationships.append(Relationship(kind: .conformance, source: qualifiedTypeName, target: supertype.typeRef.name))
        }
        if let body = node.firstChild(withType: "class_body") {
            extractBody(body, into: &typeDecl)
        }
        return typeDecl
    }

    // MARK: - Object Declaration

    private func extractObjectDeclaration(_ node: Node) -> TypeDeclaration? {
        let modifierInfo = extractModifiers(node.firstChild(withType: "modifiers"))
        guard let nameNode = node.firstChild(withType: "type_identifier") else { return nil }
        let name = text(nameNode)
        let qualifiedTypeName = qualifiedName(name)
        let supertypes = classifySupertypes(node.allChildren(withType: "delegation_specifier"))

        var typeDecl = TypeDeclaration(
            id: qualifiedTypeName, name: name, qualifiedName: qualifiedTypeName, kind: .object,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            inheritedTypes: supertypes.map(\.typeRef),
            annotations: modifierInfo.annotations, namespace: currentNamespace, location: loc(node)
        )
        for supertype in supertypes {
            relationships.append(Relationship(
                kind: supertype.isClassInheritance ? .inheritance : .conformance,
                source: qualifiedTypeName, target: supertype.typeRef.name))
        }
        if let body = node.firstChild(withType: "class_body") {
            extractBody(body, into: &typeDecl)
        }
        return typeDecl
    }

    // MARK: - Companion Object

    private func extractCompanionObject(_ node: Node) -> TypeDeclaration? {
        let name = node.firstChild(withType: "type_identifier").map { text($0) } ?? "Companion"
        let qualifiedTypeName = qualifiedName(name)
        let supertypes = classifySupertypes(node.allChildren(withType: "delegation_specifier"))

        var typeDecl = TypeDeclaration(
            id: qualifiedTypeName, name: name, qualifiedName: qualifiedTypeName,
            kind: .object, modifiers: [.static],
            inheritedTypes: supertypes.map(\.typeRef),
            namespace: currentNamespace, location: loc(node)
        )
        for supertype in supertypes {
            relationships.append(Relationship(
                kind: supertype.isClassInheritance ? .inheritance : .conformance,
                source: qualifiedTypeName, target: supertype.typeRef.name))
        }
        if let body = node.firstChild(withType: "class_body") {
            extractBody(body, into: &typeDecl)
        }
        return typeDecl
    }

    // MARK: - Enum Class

    private func extractEnumClassDeclaration(_ node: Node, modifierInfo: ModifierInfo) -> TypeDeclaration? {
        guard let nameNode = node.firstChild(withType: "type_identifier") else { return nil }
        let name = text(nameNode)
        let qualifiedTypeName = qualifiedName(name)

        let generics = extractTypeParameters(node.firstChild(withType: "type_parameters"))
        let supertypes = classifySupertypes(node.allChildren(withType: "delegation_specifier"))

        var typeDecl = TypeDeclaration(
            id: qualifiedTypeName, name: name, qualifiedName: qualifiedTypeName, kind: .enum,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            genericParameters: generics, inheritedTypes: supertypes.map(\.typeRef),
            annotations: modifierInfo.annotations, namespace: currentNamespace, location: loc(node)
        )
        for supertype in supertypes {
            relationships.append(Relationship(
                kind: supertype.isClassInheritance ? .inheritance : .conformance,
                source: qualifiedTypeName, target: supertype.typeRef.name))
        }
        if let body = node.firstChild(withType: "enum_class_body") {
            for child in body.namedChildren() where child.nodeType == "enum_entry" {
                if let enumCase = extractEnumEntry(child) { typeDecl.enumCases.append(enumCase) }
            }
            extractBody(body, into: &typeDecl, skipEnumEntries: true)
        } else if let body = node.firstChild(withType: "class_body") {
            extractBody(body, into: &typeDecl)
        }
        return typeDecl
    }

    // MARK: - Type Alias

    private func extractTypeAlias(_ node: Node) -> TypeDeclaration? {
        guard let nameNode = node.firstChild(withType: "type_identifier") else { return nil }
        let name = text(nameNode)
        let qualifiedTypeName = qualifiedName(name)
        let modifierInfo = extractModifiers(node.firstChild(withType: "modifiers"))
        let generics = extractTypeParameters(node.firstChild(withType: "type_parameters"))

        var targetType: [TypeReference] = []
        if let userTypeNode = node.firstChild(withType: "user_type") {
            targetType.append(extractTypeReference(userTypeNode))
        } else if let nullableTypeNode = node.firstChild(withType: "nullable_type") {
            targetType.append(extractNullableType(nullableTypeNode))
        }

        return TypeDeclaration(
            id: qualifiedTypeName, name: name, qualifiedName: qualifiedTypeName, kind: .typeAlias,
            accessLevel: modifierInfo.accessLevel, genericParameters: generics,
            inheritedTypes: targetType, annotations: modifierInfo.annotations,
            namespace: currentNamespace, location: loc(node)
        )
    }
}

// MARK: - Body & Member Extraction

extension KotlinExtractor {

    // MARK: - Body Extraction

    /// Extracts members, nested types, and companion objects from a class/interface/object body.
    /// Used for both `class_body` and `enum_class_body` nodes.
    private func extractBody(
        _ node: Node,
        into typeDecl: inout TypeDeclaration,
        skipEnumEntries: Bool = false
    ) {
        // Pre-scan: build property → type map for call-site resolution.
        var knownProperties: [String: String] = [:]
        for member in typeDecl.members where member.kind == .property {
            if let typeName = member.type?.name {
                knownProperties[member.name] = typeName
            }
        }
        for child in node.namedChildren()
            where child.nodeType == "property_declaration" {
            let prop = extractPropertyDeclaration(child)
            if !prop.modifiers.contains(.static),
               let typeName = prop.type?.name {
                knownProperties[prop.name] = typeName
            }
        }

        let namedChildren = node.namedChildren()
        var ctx = BodyChildContext(
            siblings: namedChildren,
            typeDecl: typeDecl,
            knownProperties: knownProperties,
            skipEnumEntries: skipEnumEntries
        )
        for (index, child) in namedChildren.enumerated() {
            handleBodyChild(child, at: index, ctx: &ctx)
        }
        typeDecl = ctx.typeDecl
    }

    private struct BodyChildContext {
        let siblings: [Node]
        var typeDecl: TypeDeclaration
        let knownProperties: [String: String]
        let skipEnumEntries: Bool
    }

    private func handleBodyChild(
        _ child: Node,
        at index: Int,
        ctx: inout BodyChildContext
    ) {
        switch child.nodeType {
        case "enum_entry" where ctx.skipEnumEntries:
            return
        case "function_declaration":
            ctx.typeDecl.members.append(
                extractFunctionDeclaration(
                    child, knownProperties: ctx.knownProperties
                )
            )
        case "property_declaration":
            let hasGetterOrSetter = nextSiblingIsAccessor(
                at: index, in: ctx.siblings
            )
            ctx.typeDecl.members.append(
                extractPropertyDeclaration(
                    child, isComputed: hasGetterOrSetter
                )
            )
        case "secondary_constructor":
            ctx.typeDecl.members.append(
                extractSecondaryConstructor(
                    child,
                    knownProperties: ctx.knownProperties
                )
            )
        case "companion_object":
            if let obj = extractCompanionObject(child) {
                ctx.typeDecl.nestedTypes.append(obj)
            }
        case "class_declaration":
            handleNestedClassDeclaration(
                child, into: &ctx.typeDecl
            )
        case "object_declaration":
            if let nestedType = extractObjectDeclaration(child) {
                ctx.typeDecl.nestedTypes.append(nestedType)
            }
        default:
            break
        }
    }

    private func nextSiblingIsAccessor(
        at index: Int, in siblings: [Node]
    ) -> Bool {
        let next = index + 1
        guard next < siblings.count else { return false }
        let sibling = siblings[next].nodeType
        return sibling == "getter" || sibling == "setter"
    }

    private func handleNestedClassDeclaration(
        _ child: Node, into typeDecl: inout TypeDeclaration
    ) {
        if child.hasDirectChildText("interface", in: context) {
            if let nestedType = extractInterfaceDeclaration(child) {
                typeDecl.nestedTypes.append(nestedType)
            }
        } else if let nestedType = extractClassDeclaration(child) {
            typeDecl.nestedTypes.append(nestedType)
        }
    }

    // MARK: - Enum Entry

    private func extractEnumEntry(_ node: Node) -> EnumCase? {
        guard let nameNode = node.firstChild(withType: "simple_identifier") else { return nil }
        let name = text(nameNode)
        var rawValue: String?
        if let valueArgs = node.firstChild(withType: "value_arguments") {
            let argsText = text(valueArgs).trimmingCharacters(in: .whitespaces)
            rawValue = (argsText.hasPrefix("(") && argsText.hasSuffix(")")) ? String(argsText.dropFirst().dropLast()) : argsText
        }
        return EnumCase(name: name, rawValue: rawValue, location: loc(node))
    }

    // MARK: - Function Declaration

    private func extractFunctionDeclaration(
        _ node: Node,
        knownProperties: [String: String] = [:]
    ) -> Member {
        let modifierInfo = extractModifiers(node.firstChild(withType: "modifiers"))
        let name = node.firstChild(withType: "simple_identifier").map { text($0) } ?? "_anonymous"
        let generics = extractTypeParameters(node.firstChild(withType: "type_parameters"))

        // Extension function receiver (e.g. `fun String.hello() {}`)
        if let receiverRef = extractReceiverType(node) {
            relationships.append(Relationship(kind: .extension, source: name, target: receiverRef.name))
        }

        let params = extractFunctionValueParameters(node.firstChild(withType: "function_value_parameters"))
        let returnType: TypeReference? = {
            guard let returnTypeNode = findReturnType(in: node) else { return nil }
            let ref = extractTypeReferenceFromAny(returnTypeNode)
            return ref.name == "Unit" ? nil : ref
        }()

        let callSites = extractCallSites(from: node.firstChild(withType: "function_body"),
                                         knownProperties: knownProperties)

        return Member(
            name: name, kind: .method,
            accessLevel: modifierInfo.accessLevel, modifiers: modifierInfo.modifiers,
            type: returnType, parameters: params,
            genericParameters: generics, annotations: modifierInfo.annotations, location: loc(node),
            callSites: callSites
        )
    }

    /// Extracts the receiver type from a Kotlin extension function declaration.
    ///
    /// In `fun String.hello() {}`, `String` is the receiver type. The tree-sitter
    /// AST places this as a type node child followed by a `"."` anonymous child
    /// before the function name.
    private func extractReceiverType(_ node: Node) -> TypeReference? {
        let children = node.children()
        guard let funIdx = children.firstIndex(where: { !$0.isNamed && text($0) == "fun" }) else { return nil }
        var childIndex = children.index(after: funIdx)
        while childIndex < children.endIndex {
            let child = children[childIndex]
            // Skip type parameters (generics before receiver)
            if child.nodeType == "type_parameters" { childIndex = children.index(after: childIndex); continue }
            // A type node followed by "." indicates a receiver type.
            if child.isNamed,
               let nodeType = child.nodeType,
               ["user_type", "nullable_type", "parenthesized_type"].contains(nodeType) {
                let nextIdx = children.index(after: childIndex)
                if nextIdx < children.endIndex,
                   !children[nextIdx].isNamed,
                   text(children[nextIdx]) == "." {
                    return extractTypeReferenceFromAny(child)
                }
            }
            break // Not an extension function
        }
        return nil
    }

    private func findReturnType(in node: Node) -> Node? {
        var foundParams = false
        var foundColon = false
        for child in node.children() {
            let childType = child.nodeType
            if childType == "function_value_parameters" { foundParams = true; continue }
            if foundParams && !child.isNamed && text(child) == ":" { foundColon = true; continue }
            if foundColon && child.isNamed {
                if ["user_type", "nullable_type", "function_type", "parenthesized_type"].contains(childType) { return child }
                break
            }
            if childType == "function_body" { break }
        }
        return nil
    }

    // MARK: - Property Declaration

    private func extractPropertyDeclaration(_ node: Node, isComputed: Bool = false) -> Member {
        let modifierInfo = extractModifiers(node.firstChild(withType: "modifiers"))
        let isVal = bindingKind(of: node) == "val"
        var modifiers = modifierInfo.modifiers
        if isVal { modifiers.append(.readonly) }

        var name = ""
        var typeRef: TypeReference?

        if let varDecl = node.firstChild(withType: "variable_declaration") {
            name = varDecl.firstChild(withType: "simple_identifier").map { text($0) } ?? ""
            typeRef = extractFirstTypeRef(from: varDecl)
        } else {
            name = node.firstChild(withType: "simple_identifier").map { text($0) } ?? ""
            typeRef = extractFirstTypeRef(from: node)
        }

        return Member(
            name: name, kind: .property,
            accessLevel: modifierInfo.accessLevel, modifiers: modifiers,
            type: typeRef,
            isComputed: isComputed,
            annotations: modifierInfo.annotations, location: loc(node)
        )
    }

    private func extractFirstTypeRef(from node: Node) -> TypeReference? {
        for child in node.namedChildren() {
            switch child.nodeType {
            case "user_type":     return extractTypeReference(child)
            case "nullable_type": return extractNullableType(child)
            case "function_type": return extractFunctionType(child)
            default: break
            }
        }
        return nil
    }

    // MARK: - Secondary Constructor

    private func extractSecondaryConstructor(
        _ node: Node,
        knownProperties: [String: String] = [:]
    ) -> Member {
        let modifierInfo = extractModifiers(node.firstChild(withType: "modifiers"))
        let params = extractFunctionValueParameters(node.firstChild(withType: "function_value_parameters"))
        let callSites = extractCallSites(from: node.firstChild(withType: "block"),
                                         knownProperties: knownProperties)
        return Member(name: "init", kind: .initializer, accessLevel: modifierInfo.accessLevel,
                      parameters: params, location: loc(node), callSites: callSites)
    }

    // MARK: - Primary Constructor Parameters

    private struct ClassParam {
        let parameter: Parameter
        let isProperty: Bool
        let isReadOnly: Bool
        let accessLevel: AccessLevel
        let modifiers: [Modifier]
        let annotations: [String]
    }

    private func extractPrimaryConstructorParams(_ node: Node?) -> [ClassParam] {
        guard let node else { return [] }
        let classParamsNode = node.firstChild(withType: "class_parameters") ?? node
        return classParamsNode.allChildren(withType: "class_parameter").map { child in
            let paramModInfo = extractModifiers(child.firstChild(withType: "modifiers"))
            let binding = bindingKind(of: child)
            let isVal = binding == "val"
            let isVar = binding == "var"
            let isProperty = isVal || isVar
            let name = child.firstChild(withType: "simple_identifier").map { text($0) } ?? ""
            let typeRef = extractFirstTypeRef(from: child)
            var defaultValue: String?
            var foundEq = false
            for innerChild in child.children() {
                if !innerChild.isNamed && text(innerChild) == "=" { foundEq = true; continue }
                if foundEq && innerChild.isNamed { defaultValue = text(innerChild); break }
            }
            return ClassParam(
                parameter: Parameter(internalName: name, type: typeRef, defaultValue: defaultValue),
                isProperty: isProperty,
                isReadOnly: isVal,
                accessLevel: paramModInfo.accessLevel,
                modifiers: paramModInfo.modifiers,
                annotations: paramModInfo.annotations
            )
        }
    }

    // MARK: - Function Value Parameters

    private func extractFunctionValueParameters(_ node: Node?) -> [Parameter] {
        guard let node else { return [] }
        return node.allChildren(withType: "parameter").map { child in
            let name = child.firstChild(withType: "simple_identifier").map { text($0) } ?? ""
            let typeRef = extractFirstTypeRef(from: child)
            var defaultValue: String?
            var foundEq = false
            for innerChild in child.children() {
                if !innerChild.isNamed && text(innerChild) == "=" { foundEq = true; continue }
                if foundEq && innerChild.isNamed { defaultValue = text(innerChild); break }
            }
            return Parameter(
                internalName: name, type: typeRef,
                defaultValue: defaultValue,
                isVariadic: hasKeyword("vararg", in: child)
            )
        }
    }
}

// MARK: - Type References & Relationships

extension KotlinExtractor {

    // MARK: - Supertype Classification

    /// A type reference paired with whether it came from a constructor invocation
    /// (class inheritance) or a bare type / delegation (interface conformance).
    private struct ClassifiedSupertype {
        let typeRef: TypeReference
        let isClassInheritance: Bool
    }

    private func classifySupertypes(_ specifiers: [Node]) -> [ClassifiedSupertype] {
        specifiers.compactMap { specifier in
            if let ctorInv = specifier.firstChild(withType: "constructor_invocation"),
               let userTypeNode = ctorInv.firstChild(withType: "user_type") {
                return ClassifiedSupertype(typeRef: extractTypeReference(userTypeNode), isClassInheritance: true)
            } else if let userTypeNode = specifier.firstChild(withType: "user_type") {
                return ClassifiedSupertype(typeRef: extractTypeReference(userTypeNode), isClassInheritance: false)
            } else if let expDel = specifier.firstChild(withType: "explicit_delegation"),
                      let userTypeNode = expDel.firstChild(withType: "user_type") {
                return ClassifiedSupertype(typeRef: extractTypeReference(userTypeNode), isClassInheritance: false)
            }
            return nil
        }
    }

    // MARK: - Type References

    private func extractTypeReferenceFromAny(_ node: Node) -> TypeReference {
        switch node.nodeType {
        case "user_type":     return extractTypeReference(node)
        case "nullable_type": return extractNullableType(node)
        case "function_type": return extractFunctionType(node)
        case "parenthesized_type":
            return node.namedChildren().first.map { extractTypeReferenceFromAny($0) }
                ?? TypeReference(name: text(node))
        default:
            return TypeReference(name: text(node))
        }
    }

    private func extractTypeReference(_ node: Node) -> TypeReference {
        var nameParts: [String] = []
        var genericArgs: [TypeReference] = []
        for child in node.namedChildren() {
            switch child.nodeType {
            case "type_identifier": nameParts.append(text(child))
            case "type_arguments":  genericArgs = extractTypeArguments(child)
            default: break
            }
        }
        return TypeReference(name: nameParts.joined(separator: "."), genericArguments: genericArgs)
    }

    private func extractNullableType(_ node: Node) -> TypeReference {
        if let inner = node.namedChildren().first {
            var ref = extractTypeReferenceFromAny(inner)
            ref.isOptional = true
            return ref
        }
        var typeName = text(node)
        if typeName.hasSuffix("?") { typeName = String(typeName.dropLast()) }
        return TypeReference(name: typeName, isOptional: true)
    }

    private func extractFunctionType(_ node: Node) -> TypeReference { TypeReference(name: text(node)) }

    private func extractTypeArguments(_ node: Node) -> [TypeReference] {
        node.namedChildren().compactMap { child in
            switch child.nodeType {
            case "type_projection":
                if let star = child.firstChild(withType: "star_projection") { return TypeReference(name: text(star)) }
                return child.namedChildren().first.map { extractTypeReferenceFromAny($0) }
            case "user_type":     return extractTypeReference(child)
            case "nullable_type": return extractNullableType(child)
            default:              return nil
            }
        }
    }

    // MARK: - Call Site Resolution

    /// Resolves `receiver.method(args)` and `this.receiver.method(args)` call patterns.
    func resolveCallSite(_ node: Node, knownProperties: [String: String]) -> CallSite? {
        guard node.nodeType == "call_expression",
              let navExpr = node.firstChild(withType: "navigation_expression")
        else { return nil }

        // Method name lives in the last navigation_suffix → simple_identifier
        guard let navSuffix = navExpr.firstChild(withType: "navigation_suffix"),
              let methodNode = navSuffix.firstChild(withType: "simple_identifier")
        else { return nil }
        let methodName = text(methodNode)

        // Resolve receiver variable name
        var receiverVarName: String?

        if let firstId = navExpr.firstChild(withType: "simple_identifier") {
            // Pattern: receiverVar.method(args)
            receiverVarName = text(firstId)
        } else if let innerNav = navExpr.firstChild(withType: "navigation_expression"),
                  innerNav.firstChild(withType: "this_expression") != nil,
                  let innerSuffix = innerNav.firstChild(withType: "navigation_suffix"),
                  let propId = innerSuffix.firstChild(withType: "simple_identifier") {
            // Pattern: this.receiverVar.method(args)
            receiverVarName = text(propId)
        }

        guard let varName = receiverVarName,
              let receiverType = knownProperties[varName]
        else { return nil }

        return CallSite(receiverType: receiverType, methodName: methodName, location: loc(node))
    }

    // MARK: - Generic Parameters

    private func extractTypeParameters(_ node: Node?) -> [GenericParameter] {
        guard let node else { return [] }
        return node.allChildren(withType: "type_parameter").compactMap { child in
            let name = child.firstChild(withType: "type_identifier").map { text($0) }
                ?? child.firstChild(withType: "simple_identifier").map { text($0) }
                ?? ""
            guard !name.isEmpty else { return nil }
            var constraints: [GenericConstraint] = []
            if let userTypeNode = child.firstChild(withType: "user_type") {
                constraints.append(GenericConstraint(kind: .conformance, type: extractTypeReference(userTypeNode)))
            } else if let nullableTypeNode = child.firstChild(withType: "nullable_type") {
                constraints.append(GenericConstraint(kind: .conformance, type: extractNullableType(nullableTypeNode)))
            }
            return GenericParameter(name: name, constraints: constraints)
        }
    }
}
